require "digest/sha1"
require 'RMagick'
require 'simple-rss'
require 'uuidtools'
require 'cgi'
class User < ActiveRecord::Base
    acts_as_taggable    
    has_settings :nil_value => ['', '0']
    belongs_to :group
    has_and_belongs_to_many :indices, :select => "distinct indices.*"
    has_many :articles, :order => 'created_at DESC'
    has_many :posts,
             :class_name => "Article",
             :conditions => ["articles.bit_opt = 0"],
             :order => 'articles.created_at DESC'
    has_many :drafts,
             :class_name => "Article",
             :conditions => ["articles.bit_opt = 2 or articles.bit_opt = 6"],
             :order => 'articles.created_at DESC'
    has_many :pages,
             :class_name => "Article",
             :conditions => ["articles.bit_opt = 4"],
             :order => 'articles.created_at DESC'
    has_many :comments,
             :class_name => "Feedback",
             :conditions => ["feedbacks.bit_opt = 1"],
             :order => "feedbacks.created_at DESC"
    has_many :messages,
             :class_name => "Feedback",
             :conditions => ["feedbacks.bit_opt = 3"],
             :order => "feedbacks.created_at DESC"
    has_many :trackbacks,
             :class_name => "Feedback",
             :conditions => ["feedbacks.bit_opt = 5"],
             :order => "feedbacks.created_at DESC"
    has_many :categories, :order => 'position'
    has_many :feedbacks, :order => 'feedbacks.created_at DESC'
    has_many :links, :order => 'position'
    attr :password
    attr_accessor :password_confirmation    
    attr_protected :group_id #, :bind_domain
    validates_presence_of :name
    validates_format_of :name, :with => /\A[a-zA-Z0-9]+\z/
    validates_uniqueness_of :name
    validates_length_of :name, :maximum => 50
    validates_confirmation_of :password
    validates_exclusion_of :name, :in => %w{ www }
    validates_presence_of :nick
    validates_presence_of :email
    #validates_uniqueness_of :email
    BASE_DIR = "#{Rails.root}/public/user_files/"
    before_create :set_default
    after_create  :create_default

    def set_default
        self.theme = "elitecircle"
        self.title = self.nick + "'s Blog"
        self.slogan = "Happy coding"
        self.admin_style = 'green'
        self.head_title = self.nick
        self.show_navbar_admin = true
        self.show_navbar_home = true
        self.show_navbar_guestbook = true
        self.show_new_comments = true
        self.show_links = true
        self.show_new_messages = true
        self.show_categories = true
        self.show_head = true
        self.show_meta = true
        self.show_rss_icon = true
        self.enable_comment_filter_simple_vcode = true
        self.group_id ||= Site.instance.default_group
        set_default_dashboard_settings
    end
    
    def create_default
        self.categories.create :name => I18n.t("activerecord.attributes.category.default_name", :default => "Uncategorized"), 
                               :info => I18n.t("activerecord.attributes.category.default_info", :default => "Uncategorized Posts")
        create_dir
    end

    def set_default_dashboard_settings
        self.show_dashboard_welcome = true
        self.dashboard_welcome_field = "chito_dashboard_left"
        self.dashboard_welcome_position = 1
        self.show_dashboard_official = true
        self.dashboard_official_field = "chito_dashboard_left"
        self.dashboard_official_position = 2
        self.show_dashboard_new_comments = true
        self.dashboard_new_comments_field = "chito_dashboard_right"
        self.dashboard_new_comments_position = 1
        self.show_dashboard_new_messages = true
        self.dashboard_new_messages_field = "chito_dashboard_right"
        self.dashboard_new_messages_position = 2
        self.show_dashboard_statistics = true
        self.dashboard_statistics_field = "chito_dashboard_right"
        self.dashboard_statistics_position = 3
        self.show_dashboard_bulletin = true
        self.dashboard_bulletin_field = "chito_dashboard_right"
        self.dashboard_bulletin_position = 4
        self.show_dashboard_posts_update = true
        self.dashboard_posts_update_field = "chito_dashboard_right"
        self.dashboard_posts_update_position = 5
        self.has_dashboard_settings = true
    end

    def is_chito_admin?
        self.get_group.name == "Admin"
    end

    def new_comments(n)
        self.comments.limit(n.to_num(5)).order('created_at desc').includes(:article)
    end

    def new_messages(n)
        self.messages.limit(n.to_num(5)).order('created_at desc').includes(:article)
    end

    def self.users_in_admin(options={})
        temp = User.order('id desc')
        temp = temp.where("users.group_id = ?", options[:group]) if options[:group]
        temp = temp.where("users.name like ?", "%#{options[:name]}%") if options[:name]
        temp = temp.where("users.name = ?", options[:user_name]) if options[:user_name]
        temp = temp.where("users.bind_domain IS NOT NULL and users.bind_domain != ''") if options[:has_bind_domain]
        temp.paginate :per_page => 30, :page => options[:page]
    end

    def find_articles(options={})
        temp = Article.where("articles.user_id = ?", self.id)
        temp = temp.where("articles.category_id = ?", options[:category_id]) if options[:category_id]
        temp = temp.order('articles.created_at desc')
        case options[:type]
            when :trash
                temp = temp.where("articles.bit_opt % 2 = 1")    
            when :posts
                temp = temp.where("articles.bit_opt = 0")
                temp = temp.order('articles.published_at desc')
            when :pages
                temp = temp.where("articles.bit_opt = 4")
            when :drafts
                temp = temp.where("(articles.bit_opt = 2 or articles.bit_opt = 6)")
        end
        temp = temp.where("articles.content like ?", "%#{options[:keyword]}%") if options[:keyword]
        if options[:year] && options[:month]
            if options[:day]
                temp = temp.where("articles.published_at >= ?", Time.mktime(options[:year].to_i, options[:month].to_i, options[:day].to_i))
                temp = temp.where("articles.published_at < ?",Time.mktime(options[:year].to_i, options[:month], options[:day].to_i) + 1.day)
            else
                temp = temp.where("articles.published_at >= ?", Time.mktime(options[:year].to_i, options[:month].to_i))
                temp = temp.where("articles.published_at < ?",Time.mktime(options[:year].to_i, options[:month]) + 1.month)
            end
        end
        if options[:tag]
            temp = temp.where("tags.name = ?", options[:tag]) 
            temp = temp.joins("INNER JOIN taggings ON articles.id = taggings.taggable_id INNER JOIN tags ON taggings.tag_id = tags.id")
        end
        temp.includes(:comments).includes(:category)\
            .paginate(:per_page => options[:per_page], :page => options[:page])
    end

    def find_talks(options={})
        Article.where("articles.user_id != ?", self.id)\
               .joins("INNER JOIN feedbacks ON feedbacks.user_name = '#{self.name}' and articles.id = feedbacks.article_id")\
               .order('articles.last_commented_at desc, articles.created_at desc')\
               .select("distinct articles.id, articles.user_id, articles.title")\
               .includes(:user)\
               .paginate(:per_page => 10, :page => options[:page])
        
        rescue
                []
    end

    def find_messages(options={})
        temp = self.messages
        temp.paginate(:per_page => options[:per_page], :page => options[:page])
    end

    def find_feedbacks(options={})
        temp = Feedback.where("feedbacks.user_id = ?", self.id)
        case options[:type]
            when :comments
                temp = temp.where("feedbacks.bit_opt = 1")
            when :messages
                temp = temp.where("feedbacks.bit_opt = 3")
            when :spams
                temp = temp.where("feedbacks.bit_opt % 2 = 0")
            when :trackbacks
                temp = temp.where("feedbacks.bit_opt = 5")
        end
        temp = temp.where("feedbacks.content like ?", "%#{options[:keyword]}%") if options[:keyword]
        temp.includes(:article).order("feedbacks.created_at desc").paginate(:per_page => options[:per_page], :page => options[:page])
    end

    def get_group
        self.group || Group.default
    end

    def bind_domain
        super.blank? ?  "- Not Specify -" : super
    end

    def used_space
        if self.cache_space < 0
            self.cache_space = Dir.size(self.base_dir) / 1024
            self.save
        end
        self.cache_space
    end

    def dirty_space
        self.cache_space = -1; self.save
    end

    def base_dir
        File.expand_path "#{Rails.root}/public/user_files/#{self.name}"
    end

    def avatar=(file)
        Dir.mkdir("#{self.base_dir}/config") unless File.exists?("#{self.base_dir}/config")  
        File.open("#{self.base_dir}/config/avatar.png", "wb") do |f| 
            f.write(file.read)
        end
        img =  Magick::Image.read("#{self.base_dir}/config/avatar.png").first
        thumb = img.resize(60, 60)
        thumb.write("#{self.base_dir}/config/avatar_small.png") 
    end

    def favicon=(file)
        File.open("#{self.base_dir}/config/favicon.ico", "wb") do |f| 
            f.write(file.read)
        end
    end

    def import_rss(url, import_category, category, import_comments, unescape_html)
        require 'open-uri'
        feed = SimpleRSS.parse(open(url).read)
        feed.items.each do |item|
            article = self.articles.build
            article.title = item.title
            if unescape_html
                cont = CGI.unescapeHTML(item.content_encoded || item.description || item.summary)
                brf =  CGI.unescapeHTML(item.description || item.summary || article.content)
            else
                cont = item.content_encoded || item.description || item.summary
                brf =  item.description || item.summary || article.content
            end 
            article.content = cont
            article.brief = brf
            #article.writer = item.author || item.dc_creator || self.nick
            article.created_at = item.pubDate || item.dc_date || Time.now
            article.tag_list = item.the_tags
            article.seo_title = item.seo_title
            if import_category == 'default_category' || item.category.blank?
                article.category = self.categories.find(category)
            else
                new_category = self.categories.find_by_name(item.category)
                new_category ||= self.categories.create(:name => item.category, :info => t(:message_12, :scope => [:txt, :model, :user]))
                article.category = new_category
            end
            article.save
            if import_comments and item.wfw_commentRSS
                curl = item.wfw_commentRss || item.wfw_commentRSS
                cfeed = SimpleRSS.parse(open(curl).read)
                cfeed.items.each do |item|
                    comment = Feedback.new
                    comment.pass = true
                    comment.article_id = article.id
                    comment.user_id = self.id
                    comment.writer = item.author || item.dc_creator || item.title
                    comment.content = item.content_encoded || item.description || item.summary
                    comment.created_at = item.pubDate || item.dc_date
                    comment.save
                end
            end
        end
        return true
    end

    def password=(pwd)
        @password = pwd
        return if pwd.blank?
        create_salt
        self.hashed_password = User.hash_password(self.password, self.salt)
    end

    def set_session(session, request, site)
        session[:user_id] = self.id
        session[:user_name] = self.name
        session[:user_nick] = self.nick
        session[:email] = self.email
        if request.domain != site.domain and self.bind_domain
            session[:bind_domain] = self.bind_domain
        end
    end

    def remember_me(cookies, request, time = 1.week)
        self.remember_key_expires_at = time.from_now.utc
        self.remember_key = UUIDTools::UUID.random_create.to_s
        self.save#(false)
        cookies[:remember_key] = {:value => self.remember_key, :expires => self.remember_key_expires_at, :path => '/admin', :httponly => true, :domain => request.domain }
    end

    def forgot_password(request, time = 1.day)
        self.reset_password_key = UUIDTools::UUID.random_create.to_s
        self.reset_password_key_expires_at = time.from_now.utc
        ChitoMailer.forgot_password(self, request).deliver if self.save
    end

    def self.login(name, password)
        user = User.find_by_name(name)
        if user
            expected_password = hash_password(password, user.salt)
            user = nil if user.hashed_password != expected_password
        end
        user
    end

    def avatar_url(options={})
        avatar = Dir[File.join(self.base_dir, "config", "{avatar.png,head.jpg}")].sort.first
        if avatar       
            "/user_files/#{self.name}/config/#{File.basename(avatar)}"
        else
           "/user_files/avatar.png"
        end     
    end

    def small_avatar_url(options={})
        avatar = Dir[File.join(self.base_dir, "config", "{avatar_small.png,head_small.jpg}")].sort.first
        if avatar       
            "/user_files/#{self.name}/config/#{File.basename(avatar)}"
        else
           "/user_files/avatar_small.png"
        end     
    end

    def error_messages
        self.errors.map{|x| x[1]}.join("; ")
    end

    # Fix of Psych YAML persing problem with Syck data.
    def fix_settings
        s = self.settings
        new_s = {}
        return unless s.is_a?(Hash)
        s.each do |key, value|
            if value.is_a?(String)
                begin
                    new_value = value.clone.force_encoding("UTF-8").encode("ISO-8859-1").force_encoding("UTF-8")
                rescue
                    new_value = value
                end
            else
                new_value = value
            end
            new_s[key] = new_value
        end
        self.settings = new_s
        self.settings_will_change!
        self.save
    end

    def self.fix_all_settings
        self.all.each do |u|
            u.fix_settings
        end
    end

    def create_dir
        Dir.mkdir(self.base_dir,0775) unless File.exists?(self.base_dir)
        Dir.mkdir("#{self.base_dir}/config",0775) unless File.exists?("#{self.base_dir}/config")
        Dir.mkdir("#{self.base_dir}/themes",0775) unless File.exists?("#{self.base_dir}/themes")
        Dir.mkdir("#{self.base_dir}/File",0775) unless File.exists?("#{self.base_dir}/File")
        Dir.mkdir("#{self.base_dir}/Image",0775) unless File.exists?("#{self.base_dir}/Image")
    end

    private

    def self.hash_password(password, salt)
        str = password.dup
        ( str << "galeki" << salt ) unless salt.nil?
        Digest::SHA1.hexdigest(str)
    end
    
    def create_salt
        self.salt = UUIDTools::UUID.random_create.to_s
    end


end
