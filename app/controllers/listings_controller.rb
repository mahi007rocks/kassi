class ListingsController < ApplicationController

  before_filter :save_current_path, :only => :show
  before_filter :ensure_authorized_to_view, :only => :show

  before_filter :only => [ :new, :create ] do |controller|
    controller.ensure_logged_in "you_must_log_in_to_create_new_#{params[:type]}"
  end
  
  before_filter :only => [ :edit, :update, :close ] do |controller|
    controller.ensure_logged_in "you_must_log_in_to_view_this_content"
  end
  
  before_filter :only => [ :close ] do |controller|
    controller.ensure_current_user_is_listing_author "only_listing_author_can_close_a_listing"
  end
  
  before_filter :only => [ :edit, :update ] do |controller|
    controller.ensure_current_user_is_listing_author "only_listing_author_can_edit_a_listing"
  end
  
  def index
    redirect_to root
  end
  
  def requests
    params[:listing_type] = "request"
    @to_render = {:action => :index}
    @listing_style = "listing"
    load
  end
  
  def offers
    params[:listing_type] = "offer"
    @to_render = {:action => :index}
    @listing_style = "listing"
    load
  end

  # detect the browser and return the approriate layout
  def detect_browser
    if APP_CONFIG.force_mobile_ui
        return true
    end
    
    mobile_browsers = ["android", "ipod", "opera mini", "blackberry", 
"palm","hiptop","avantgo","plucker", "xiino","blazer","elaine", "windows ce; ppc;", 
"windows ce; smartphone;","windows ce; iemobile", 
"up.browser","up.link","mmp","symbian","smartphone", 
"midp","wap","vodafone","o2","pocket","kindle", "mobile","pda","psp","treo"]
    if request.headers["HTTP_USER_AGENT"]
	    agent = request.headers["HTTP_USER_AGENT"].downcase
	    mobile_browsers.each do |m|
		    return true if agent.match(m)
	    end    
    end
    return false
  end
    

  # Used to load listings to be shown
  # How the results are rendered depends on 
  # the type of request and if @to_render is set
  def load
    @title = params[:listing_type]
    @tag = params[:tag]
    @to_render ||= {:partial => "listings/listed_listings"}
    @listings = Listing.open.order("created_at DESC").find_with(params, @current_user).paginate(:per_page => 15, :page => params[:page])
    @request_path = request.fullpath
    @check_mobile = detect_browser
    if @check_mobile
      @title = params[:listing_type]
      @listings_temp = Listing.open.joins(:origin_loc).order("locations.latitude ASC, locations.longitude ASC").find_with(params, @current_user)
      
      @userlocation = Hash.new
      if (!@current_user.nil? && !@current_user.location.nil?)
        @userlocation['lat'] = @current_user.location.latitude
        @userlocation['long'] = @current_user.location.longitude
      else
        @userlocation = nil
      end
      
      @locations = Array.new
      @listings = Array.new
      
      for i in 0..(@listings_temp.length-1)
        if (i == 0) or (@listings_temp[i].origin_loc.latitude != @listings_temp[i-1].origin_loc.latitude) or (@listings_temp[i].origin_loc.longitude != @listings_temp[i-1].origin_loc.longitude)
            location_temp = Hash.new
            location_temp['lat'] = @listings_temp[i].origin_loc.latitude
            location_temp['long'] = @listings_temp[i].origin_loc.longitude
            @locations.push location_temp
            
            listing_temp = Hash.new
            listing_temp['id'] = Array.new
            listing_temp['title'] = Array.new
            listing_temp['description'] = Array.new       
            listing_temp['category'] = Array.new
            listing_temp['id'].push @listings_temp[i].id
            listing_temp['title'].push @listings_temp[i].title
            listing_temp['description'].push @listings_temp[i].description   
            listing_temp['category'].push @listings_temp[i].category
            @listings.push listing_temp            
        else
            @listings[@listings.length - 1]['id'].push @listings_temp[i].id
            @listings[@listings.length - 1]['title'].push @listings_temp[i].title
            @listings[@listings.length - 1]['description'].push @listings_temp[i].description
            @listings[@listings.length - 1]['category'].push @listings_temp[i].category
        end  
      end
      
      render :partial => "listings/mobile_listings"
    else
      @title = params[:listing_type]
      @to_render ||= {:partial => "listings/listed_listings"}
      @listings = Listing.open.order("created_at DESC").find_with(params, @current_user).paginate(:per_page => 15, :page => params[:page])
      @request_path = request.fullpath
      if request.xhr? && params[:page] && params[:page].to_i > 1
        render :partial => "listings/additional_listings"
      else
        render  @to_render
      end
    end
  end 
  
  def loadmap
    @title = params[:listing_type]
    @listings = Listing.open.order("created_at DESC").find_with(params, @current_user)
    @listing_style = "map"
    @to_render ||= {:partial => "listings/listings_on_map"}
    @request_path = request.fullpath
    render  @to_render
  end

  # The following two are simple dummy implementations duplicating the
  # functionality of normal listing methods.
  def requests_on_map
    params[:listing_type] = "request"
    @to_render = {:action => :index}
    @listings = Listing.open.order("created_at DESC").find_with(params, @current_user)
    @listing_style = "map"
    load
  end

  def offers_on_map
    params[:listing_type] = "offer"
    @to_render = {:action => :index}
    @listing_style = "map"
    load
  end
  
  
  # A (stub) method for serving Listing data (with locations) as JSON through AJAX-requests.
  def serve_listing_data
    
    @listings = Listing.includes(:share_types, :location, :author).open.joins(:location).group(:id).
                order("created_at DESC").find_with(params, @current_user)
    
    
    render :json => { :data => @listings }
  end
  
  def listing_bubble
    if params[:id] then
      @listing = Listing.find params[:id]
      render :partial => "homepage/recent_listing", :locals => {:listing => @listing}
    end 
  end
  
  def listing_all_bubbles
      @listings = Listing.includes(:share_types, :location, :author).open.joins(:location).group(:id).
                order("created_at DESC").find_with(params, @current_user)
      @render_array = [];
      @listings.each do |listing|
        @render_array[@render_array.length] = render_to_string :partial => "homepage/recent_listing", :locals => {:listing => listing}
      end
      render :json => { :info => @render_array }
  end

  def show
    @listing.increment!(:times_viewed)
  end
  
  def new
    @listing = Listing.new
    @listing.listing_type = params[:type]
    @listing.category = params[:category] || "item"
    if @listing.category == "rideshare"
	    @listing.build_origin_loc(:location_type => "origin_loc")
	    @listing.build_destination_loc(:location_type => "destination_loc")
    else
	    if (@current_user.location != nil)
	      temp = @current_user.location
	      temp.location_type = "origin_loc"
	      @listing.build_origin_loc(temp.attributes)
      else
	      @listing.build_origin_loc(:location_type => "origin_loc")
      end
    end
    1.times { @listing.listing_images.build }
    if @listing.category != "rideshare"
      @listing.build_location
    else
      @listing.build_origin_loc
      @listing.build_destination_loc
    end
    respond_to do |format|
      format.html
      format.js {render :layout => false}
    end
  end
  
  def create
	  if params[:listing][:origin_loc_attributes][:address].empty?
	    params[:listing].delete("origin_loc_attributes")
	  end
    @listing = @current_user.create_listing params[:listing]
    if @listing.category != "rideshare"
      @location = @listing.create_location(params[:location])
    else
      @origin_loc = @listing.create_origin_loc(params[:origin_loc])
      @destination_loc = @listing.create_destination_loc(params[:destination_loc])
    end
    if @listing.new_record?
      1.times { @listing.listing_images.build } if @listing.listing_images.empty?
      render :action => :new
    else
      path = new_request_category_path(:type => @listing.listing_type, :category => @listing.category)
      flash[:notice] = ["#{@listing.listing_type}_created_successfully", "create_new_#{@listing.listing_type}".to_sym, path]
      Delayed::Job.enqueue(ListingCreatedJob.new(@listing.id, request.host))
      redirect_to @listing
    end
  end
  
  def edit
	  if !@listing.origin_loc
	      @listing.build_origin_loc(:location_type => "origin_loc")
	  end
    1.times { @listing.listing_images.build } if @listing.listing_images.empty?
  end
  
  def update
  if params[:listing][:origin_loc_attributes][:address].empty?
    params[:listing].delete("origin_loc_attributes")
    if @listing.origin_loc
     @listing.origin_loc.delete
    end
  end
    if @listing.update_fields(params[:listing])
      @listing.location.update_attributes(params[:location]) if @listing.location
      flash[:notice] = "#{@listing.listing_type}_updated_successfully"
      redirect_to @listing
    else
      render :action => :edit
    end    
  end
  
  def close
    @listing.update_attribute(:open, false)
    flash.now[:notice] = "#{@listing.listing_type}_closed"
    respond_to do |format|
      format.html { redirect_to @listing }
      format.js { render :layout => false }
    end
  end
  
  #shows a random listing (that is visible to all)
  def random
    conditions = "open = 1 AND valid_until >= '" + DateTime.now.to_s + "' AND visibility = 'everybody'"
        
    open_listings_ids = Listing.select("id").where(conditions).all
    random_id = open_listings_ids[Kernel.rand(open_listings_ids.length)].id
    #redirect_to listing_path(random_id)
    @listing = Listing.find_by_id(random_id)
    render :action => :show
  end
  
  def ensure_current_user_is_listing_author(error_message)
    @listing = Listing.find(params[:id])
    return if current_user?(@listing.author) || @current_user.is_admin?
    flash[:error] = error_message
    redirect_to @listing and return
  end
  
  private
  
  # Ensure that only users with appropriate visibility settings can view the listing
  def ensure_authorized_to_view
    @listing = Listing.find(params[:id])
    if @current_user
      unless @listing.visible_to?(@current_user)
        flash[:error] = "you_are_not_authorized_to_view_this_content"
        redirect_to root and return
      end
    else
      unless @listing.visibility.eql?("everybody")
        session[:return_to] = request.fullpath
        flash[:warning] = "you_must_log_in_to_view_this_content"
        redirect_to new_session_path and return
      end
    end
  end

end
