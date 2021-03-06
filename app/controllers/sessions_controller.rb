require 'rest_client'

class SessionsController < ApplicationController
  include UrlHelper
  
  skip_filter :check_email_confirmation
  skip_filter :dashboard_only
  skip_filter :single_community_only, :only => [ :create, :request_new_password ]
  skip_filter :cannot_access_without_joining, :only => [ :destroy, :confirmation_pending ]
  skip_filter :not_public_in_private_community, :only => [ :create, :request_new_password ]
  
  # For security purposes, Devise just authenticates an user
  # from the params hash if we explicitly allow it to. That's
  # why we need to call the before filter below.
  before_filter :allow_params_authentication!, :only => :create
 
  def new
    @facebook_merge = session["devise.facebook_data"].present?
    if @facebook_merge
      @facebook_email = session["devise.facebook_data"]["email"]
      @facebook_name = "#{session["devise.facebook_data"]["given_name"]} #{session["devise.facebook_data"]["family_name"]}"
    end
  end
 
  def create
 
    if current_community = Community.find_by_domain(params[:community])
      domain = "http://#{with_subdomain(current_community.domain)}"
    else
      domain = "http://www.#{[request.domain, request.port_string].join}"
    end

    session[:form_username] = params[:person][:username]
    
    if use_asi?
      # Start a session with ASI
      
      begin
        @session = Session.create({ :username => params[:person][:username], 
          :password => params[:person][:password] })
          if @session.person_id  # if not app-only-session and person found in cos
            @current_user = Person.find_by_id(@session.person_id)
          end
      rescue RestClient::Unauthorized => e
        flash[:error] = :login_failed
        if current_community.private?
          redirect_to "#{domain}/#{I18n.locale}/homepage/sign_in" and return
        else
          redirect_to domain + login_path and return
        end
      end
      
      
    else
      # Start a session with Devise
      
      # In case of failure, set the message already here and 
      # clear it afterwards, if authentication worked.
      flash[:error] = :login_failed
      
      # Since the authentication happens in the rack layer,
      # we need to tell Devise to call the action "sessions#new"
      # in case something goes bad.
      if current_community
        if current_community.private?
          person = authenticate_person!(:recall => "homepage#sign_in")
        else
          person = authenticate_person!(:recall => "sessions#new")
        end
      else
        person = authenticate_person!(:recall => "dashboard#login")
      end
      flash[:error] = nil
      @current_user = person
      
      # Store Facebook ID and picture if connecting with FB
      if session["devise.facebook_data"]
        @current_user.update_attribute(:facebook_id, session["devise.facebook_data"]["id"]) 
        # FIXME: Currently this doesn't work for very unknown reason. Paper clip seems to be processing, but no pic
        if @current_user.image_file_size.nil?
          @current_user.store_picture_from_facebook
        end
      end
      
      sign_in @current_user

    end

    session[:form_username] = nil
    
    unless @current_user && (!@current_user.communities.include?(@current_community) || current_community.consent.eql?(@current_user.consent(current_community)) || @current_user.is_admin?)
      # Either the user has succesfully logged in, but is not found in Kassi DB
      # (Existing OtaSizzle user's first login in Kassi) or the user is a member
      # of this community but the terms of use have changed.
      if use_asi?
        session[:temp_cookie] = @session.cookie
        session[:temp_person_id] = @session.person_id
      else
        sign_out @current_user
        session[:temp_cookie] = "pending acceptance of new terms"
        session[:temp_person_id] =  @current_user.id  
      end
      session[:temp_community_id] = current_community.id
      session[:consent_changed] = true if @current_user
      redirect_to domain + terms_path and return
    end
    
    if use_asi?
      session[:cookie] = @session.cookie
      session[:person_id] = @session.person_id 
    else
      session[:person_id] = current_person.id
    end
    
    @current_user.update_attribute(:active, true) unless @current_user.active?
    
    if not @current_community
      redirect_to domain + new_tribe_path
    elsif @current_user.communities.include?(@current_community) || @current_user.is_admin?
      flash[:notice] = [:login_successful, (@current_user.given_name_or_username + "!").to_s, person_path(@current_user)]
      EventFeedEvent.create(:person1_id => @current_user.id, :community_id => current_community.id, :category => "login") unless (@current_user.is_admin? && !@current_user.communities.include?(@current_community))
      if session[:return_to]
        redirect_to domain + session[:return_to]
        session[:return_to] = nil
      else
        redirect_to domain + root_path
      end
    else
      redirect_to domain + new_tribe_membership_path
    end
  end

  def destroy
    if use_asi?
      Session.destroy(session[:cookie]) if session[:cookie]
    else
      sign_out
    end
    session[:cookie] = nil
    session[:person_id] = nil
    flash[:notice] = :logout_successful
    redirect_to root
  end
  
  def index
    # this is not in use in Kassi, but bots seem to try the url so implementing this to avoid errors
    render :file => "#{RAILS_ROOT}/public/404.html", :layout => false, :status => 404
  end
  
  def request_new_password
    if use_asi?
      begin
        RestHelper.make_request(:post, "#{APP_CONFIG.asi_url}/people/recover_password", {:email => params[:email]} ,{:cookies => Session.kassi_cookie})
        # RestClient.post("#{APP_CONFIG.asi_url}/people/recover_password", {:email => params[:email]} ,{:cookies => Session.kassi_cookie})
        flash[:notice] = :password_recovery_sent
      rescue RestClient::ResourceNotFound => e 
        flash[:error] = :email_not_found
      end
    else
      if Person.find_by_email(params[:email])
        #Call devise based method
        resource = Person.send_reset_password_instructions(params)
        flash[:notice] = :password_recovery_sent
      else
        flash[:error] = :email_not_found
      end
    end
    
    if on_dashboard?
      redirect_to dashboard_login_path
    elsif @current_community && @current_community.private?
      redirect_to :controller => :homepage, :action => :sign_in
    else
      redirect_to login_path
    end
  end
  
  def facebook
    @person = Person.find_for_facebook_oauth(request.env["omniauth.auth"], @current_user)

    I18n.locale = exctract_locale_from_url(request.env['omniauth.origin']) if request.env['omniauth.origin']
    
    if @person
      flash[:notice] = t("devise.omniauth_callbacks.success", :kind => "Facebook")
      sign_in_and_redirect @person, :event => :authentication
    else
      data = request.env["omniauth.auth"].extra.raw_info
      facebook_data = {"email" => data.email,
                       "given_name" => data.first_name,
                       "family_name" => data.last_name,
                       "username" => data.username,
                       "id"  => data.id}

      session["devise.facebook_data"] = facebook_data
      redirect_to :action => :new
    end
  end
  
  # Callback from Omniauth failures
  def failure    
    I18n.locale = exctract_locale_from_url(request.env['omniauth.origin']) if request.env['omniauth.origin']
    error_message = params[:error_reason] || "login error"
    kind = env["omniauth.error.strategy"].name.to_s || "Facebook"
    flash[:error] = t("devise.omniauth_callbacks.failure",:kind => kind.humanize, :reason => error_message.humanize)
    redirect_to root
  end
  
  # This is used if user has not confirmed her email address
  def confirmation_pending
    
  end
  
end
