class Community < ActiveRecord::Base

  has_many :community_memberships, :dependent => :destroy 
  has_many :members, :through => :community_memberships, :source => :person, :foreign_key => :member_id
  has_many :invitations, :dependent => :destroy
  has_many :news_items
  has_many :polls
  has_many :event_feed_events
  has_one :location, :dependent => :destroy
  
  has_and_belongs_to_many :listings
  
  VALID_CATEGORIES = ["company", "university", "association", "neighborhood", "congregation", "town", "apartment_building", "other"]
  
  validates_length_of :name, :in => 2..50
  validates_length_of :domain, :in => 2..50
  validates_format_of :domain, :with => /^[A-Z0-9_-]*$/i
  validates_uniqueness_of :domain
  validates_length_of :slogan, :in => 2..100, :allow_nil => true
  validates_length_of :description, :in => 2..500, :allow_nil => true
  validates_inclusion_of :category, :in => VALID_CATEGORIES
  
  # The settings hash contains some community specific settings:
  # locales: which locales are in use, the first one is the default
  # asi_welcome_mail: boolean that tells if ASI should send the welcome mail to newly registered user. Default is false.
    
  serialize :settings, Hash
  
  attr_accessor :terms
  
  def address
    location ? location.address : nil
  end
  
  def default_locale
    if settings && !settings["locales"].blank?
      return settings["locales"].first
    else
      return APP_CONFIG.default_locale
    end
  end
  
  def locales
   if settings && !settings["locales"].blank?
      return settings["locales"]
    else
      # if locales not set, return the short locales from the default list
      return APP_CONFIG.available_locales.collect{|loc| loc[1]}
    end
  end
  
  # Return the people who are admins of this community
  def admins
    members.joins(:community_memberships).where("community_memberships.admin = '1'").group("people.id")
  end
  
  # Returns the emails of admins in an array
  def admin_emails
    admins.collect { |p| p.email }
  end
  
  # returns if ASI welcome mail is used for this community
  # defaults to false if that setting is not set
  def use_asi_welcome_mail?
    if settings && settings["asi_welcome_mail"] == true
      return true
    else
      return false
    end
  end
  
  # If community name has several words, add an extra space
  # to the end to make Finnish translation look better.
  def name_with_separator(locale)
    (name.include?(" ") && locale.to_s.eql?("fi")) ? "#{name} " : name
  end
  
  def active_poll
    polls.where(:active => true).first
  end
  
  def set_email_confirmation_on_and_send_mail_to_existing_users
    # If email confirmation is already active, do nothing
    return if self.email_confirmation == true
    
    self.email_confirmation = true
    save
    
    original_locale = I18n.locale
    
    #Store host to global variable to be able to use this from console
    $host = "#{self.domain}.#{APP_CONFIG.weekly_email_domain}"
    
    members.all.each do |member|
      member.confirmed_at = nil
      member.save
      I18n.locale = member.locale
      member.send_confirmation_instructions
      
    end
    I18n.locale = original_locale
  end
  
  def email_all_members(subject, mail_content, default_locale="en", verbose=false)
    puts "Sending mail to all #{members.count} members in community: #{self.name}" if verbose
    PersonMailer.deliver_open_content_messages(members.all, subject, mail_content, default_locale, verbose)
  end

  # Makes the creator of the community a member and an admin
  def admin_attributes=(attributes)
    community_memberships.build(attributes)
  end
  
  def self.domain_available?(domain)
    reserved_names = %w{ www wiki mail calendar doc docs admin dashboard translate alpha beta gamma test developer community tribe git partner partners global sharetribe share dev st aalto ospn kassi video photos fi fr cl gr us usa}
    ! (reserved_names.include?(domain) || find_by_domain(domain).present?)
  end
  
  def self.find_by_email_ending(email)
    Community.all.each do |community|
      return community if community.allowed_emails && community.email_allowed?(email)
    end
    return nil
  end
  
  def email_allowed?(email)
    Community.find_by_email_ending
  end
  
  def self.email_allowed?(email)
    allowed = false
    allowed_array = allowed_emails.split(",")
    allowed_array.each do |allowed_domain_or_address|
      allowed_domain_or_address.strip!
      allowed_domain_or_address.gsub!('.', '\.') #change . to be \. to only match a dot, not any char
      if email =~ /#{allowed_domain_or_address}$/
        allowed = true
        break
      end
    end
    return allowed
  end

end
