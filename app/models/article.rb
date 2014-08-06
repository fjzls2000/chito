require 'net/http'
require 'uri'
class Article < ActiveRecord::Base
    acts_as_taggable
    has_settings :nil_value => ['', '0']
    has_flags [:is_deleted, :is_draft, :is_page], [:column => 'bit_opt']
    belongs_to :user 
    belongs_to :index 
    has_many :comments, 
             :class_name => 'Feedback',
             :order => 'feedbacks.created_at', 
             :conditions => ["feedbacks.bit_opt = 1"],
             :dependent => :destroy
    has_many :trackbacks, 
             :class_name => 'Feedback',
             :order => 'feedbacks.created_at', 
             :conditions => ["feedbacks.bit_opt = 5"],
             :dependent => :destroy
    belongs_to :category
    attr_protected :read_count, :rank
    include ArticlePlugin

    def self.new_posts(num=20)
        where("articles.bit_opt = 0 and articles.rank >= 1").order('articles.published_at DESC').limit(num)
    end

    def self.new_ranked_posts(options)
        temp = self.where("articles.index_id = ? and articles.bit_opt = 0 and articles.rank > ?", options[:index_id], options[:rank])
        temp = temp.where("articles.content like ?", "%#{options[:keyword]}%") if options[:keyword]
        temp.order("articles.published_at DESC")\
            .includes(:user).includes(:comments)\
            .paginate(:per_page => (options[:per_page] || 10), :page => options[:page])
    end

    def title
        super.blank? ? t(:message_0, :scope => [:txt, :model, :article]) : super
        rescue 
            "No Title"
    end

    def prepare(user, params)
        self.bit_opt_will_change!
        self.attributes = params[:article]
        self.user_id = user.id
        self.category = params[:category] ? user.categories.find(params[:category]) : user.categories.order('position').first
    end

    def make_brief
        return unless self.auto_brief
        index = self.content.index('<!--more-->')
        if index
            s = content[0,index]
            self.has_more = true
            self.brief = close_html(s)
        else
            self.has_more = false
        end
    end

    def trackback_key
        str = "#{self.title}-#{self.created_at}-#{self.user_id}-#{self.trackbacks.size / 5}"
        Digest::SHA1.hexdigest(str)
    end

    def trackback_params
        {:title => self.title,
            :excerpt => helpers.truncate(helpers.strip_tags(self.brief), :length => 200),
            :blog_name => self.user.title}
    end

    def brief
        (self.auto_brief && !self.has_more) ? self.content : "<p>#{super}</p>".html_safe
    end

    def prev
        self.category.posts.where("created_at < ? and bit_opt = 0 ", self.created_at).first if self.category
    end

    def next
        self.category.posts.where("created_at > ? and bit_opt = 0 ", self.created_at).last if self.category
    end

    def last_comment
        Feedback.where("feedbacks.article_id = ? and feedbacks.bit_opt = 1", self.id).order('feedbacks.created_at').last
    end

    def to_xml(options={})
        only = {:only => [:title, :created_at, :content, :writer]}
        super only.merge(options)
    end

    def short_brief(n)
        helpers.truncate(helpers.strip_tags(self.brief.to_s).gsub(/(&nbsp;)|(&#160;)/,''), :length => n).html_safe
    end

    def content_blank?
        helpers.strip_tags(self.content).gsub(/(&nbsp;)|(&#160;)/,'').blank?
    end

    def type
        return :draft if self.is_draft?
        return :page if self.is_page?
        return :post
    end

    def published_or_created_time
        self.published_at || self.created_at
    end

    def parameterize_permalink
        self.permalink.to_s.parameterize
    end

    private

    def close_html(html)
        stream = html.scan(/<\s*[\/]*[^>^\/]+>/).map {|x| x[/<\s*([^>^\s]*)[^>]*>/, 1]}
        stack = []
        stream.each do |x|
            if x =~ /^\//
                stack.pop if x[1..-1] == stack.last
            else
                stack.push x
            end
        end
        stack.reverse.each {|x| html << "</#{x}>\n"}
        html
    end 

end
