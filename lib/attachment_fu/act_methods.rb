module AttachmentFu
  module ActMethods
    # Options:
    # *  <tt>:content_type</tt> - Allowed content types.  Allows all by default.  Use :image to allow all standard image types.
    # *  <tt>:min_size</tt> - Minimum size allowed.  1 byte is the default.
    # *  <tt>:max_size</tt> - Maximum size allowed.  1.megabyte is the default.
    # *  <tt>:size</tt> - Range of sizes allowed.  (1..1.megabyte) is the default.  This overrides the :min_size and :max_size options.
    # *  <tt>:resize_to</tt> - Used by RMagick to resize images.  Pass either an array of width/height, or a geometry string.  Prefix geometry string with 'c' to crop image, ex. 'c100x100'
    # *  <tt>:sharpen_on_resize</tt> - When using RMagick, setting to true will sharpen images after resizing.
    # *  <tt>:jpeg_quality</tt> - Used to provide explicit JPEG quality for thumbnail/resize saves.  Can have multiple formats:
    #      * Integer from 0 (basically crap) to 100 (basically lossless, fat files).
    #      * When relying on ImageScience, you can also use one of its +JPEG_xxx+ constants for predefined ratios/settings.
    #      * You can also use a Hash, with keys being either  thumbnail symbols (I repeat: _symbols_) or surface boundaries.
    #        A surface boundary is a string starting with either '<' or '>=', followed by a number of pixels.  This lets you
    #        specify per-thumbnail or per-general-thumbnail-"size" JPEG qualities. (which can be useful when you have a
    #        _lot_ of thumbnail options).  Surface example:  +{ '<2000' => 90, '>=2000' => 75 }+.
    #      Defaults vary depending on the processor (ImageScience: 100%, Rmagick/MiniMagick: 75%,
    #      ). Note that only tdd-image_science (available from GitHub) currently supports explicit JPEG quality;
    #      the default image_science currently forces 100%.
    # *  <tt>:thumbnails</tt> - Specifies a set of thumbnails to generate.  This accepts a hash of filename suffixes and
    #      RMagick resizing options.  If you have a polymorphic parent relationship, you can provide parent-type-specific
    #      thumbnail settings by using a pair with the type string as key and a Hash of thumbnail definitions as value.
    #      AttachmentFu automatically detects your first polymorphic +belongs_to+ relationship.
    # *  <tt>:thumbnail_class</tt> - Set what class to use for thumbnails.  This attachment class is used by default.
    # *  <tt>:path_prefix</tt> - path to store the uploaded files.  Uses public/#{table_name} by default for the filesystem, and just #{table_name}
    #      for the S3 backend.  Setting this sets the :storage to :file_system.

    # *  <tt>:storage</tt> - Use :file_system to specify the attachment data is stored with the file system.  Defaults to :db_system.
    # *  <tt>:cloundfront</tt> - Set to true if you are using S3 storage and want to serve the files through CloudFront.  You will need to
    #      set a distribution domain in the amazon_s3.yml config file. Defaults to false
    # *  <tt>:bucket_key</tt> - Use this to specify a different bucket key other than :bucket_name in the amazon_s3.yml file.  This allows you to use
    #      different buckets for different models. An example setting would be :image_bucket and the you would need to define the name of the corresponding
    #      bucket in the amazon_s3.yml file.

    # *  <tt>:keep_profile</tt> By default image EXIF data will be stripped to minimize image size. For small thumbnails this proivides important savings. Picture quality is not affected. Set to false if you want to keep the image profile as is. ImageScience will allways keep EXIF data.
    #
    # Examples:
    #   has_attachment :max_size => 1.kilobyte
    #   has_attachment :size => 1.megabyte..2.megabytes
    #   has_attachment :content_type => 'application/pdf'
    #   has_attachment :content_type => ['application/pdf', 'application/msword', 'text/plain']
    #   has_attachment :content_type => :image, :resize_to => [50,50]
    #   has_attachment :content_type => ['application/pdf', :image], :resize_to => 'x50'
    #   has_attachment :thumbnails => { :thumb => [50, 50], :geometry => 'x50' }
    #   has_attachment :storage => :file_system, :path_prefix => 'public/files'
    #   has_attachment :storage => :file_system, :path_prefix => 'public/files',
    #     :content_type => :image, :resize_to => [50,50]
    #   has_attachment :storage => :file_system, :path_prefix => 'public/files',
    #     :thumbnails => { :thumb => [50, 50], :geometry => 'x50' }
    #   has_attachment :storage => :s3
    def has_attachment(options = {})
      # this allows you to redefine the acts' options for each subclass, however
      options[:min_size]         ||= 1
      options[:max_size]         ||= 1.megabyte
      options[:size]             ||= (options[:min_size]..options[:max_size])
      options[:thumbnails]       ||= {}
      options[:thumbnail_class]  ||= self
      options[:s3_access]        ||= :public_read
      options[:cloudfront]       ||= false
      options[:content_type] = [options[:content_type]].flatten.collect! { |t| t == :image ? ::AttachmentFu.content_types : t }.flatten unless options[:content_type].nil?
      options[:cache_control]    ||= "max-age=315360000" # 10 years

      unless options[:thumbnails].is_a?(Hash)
        raise ArgumentError, ":thumbnails option should be a hash: e.g. :thumbnails => { :foo => '50x50' }"
      end

      extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
      include InstanceMethods unless included_modules.include?(InstanceMethods)

      parent_options = attachment_options || {}
      # doing these shenanigans so that #attachment_options is available to processors and backends
      self.attachment_options = options

      attr_accessor :thumbnail_resize_options

      attachment_options[:storage]     ||= (attachment_options[:file_system_path] || attachment_options[:path_prefix]) ? :file_system : :db_file
      attachment_options[:storage]     ||= parent_options[:storage]
      attachment_options[:path_prefix] ||= attachment_options[:file_system_path]
      if attachment_options[:path_prefix].nil?
        attachment_options[:path_prefix] = case attachment_options[:storage]
                                           when :s3 then table_name
                                           when :cloud_files then table_name
                                           else File.join("public", table_name)
                                           end
      end
      attachment_options[:path_prefix]   = attachment_options[:path_prefix][1..-1] if options[:path_prefix].first == '/'

      association_options = { :foreign_key => 'parent_id' }
      if attachment_options[:association_options]
        association_options.merge!(attachment_options[:association_options])
      end
      with_options(association_options) do |m|
        m.has_many   :thumbnails, :class_name => "::#{attachment_options[:thumbnail_class]}"
        m.belongs_to :parent, :class_name => "::#{base_class}" unless options[:thumbnails].empty?
      end

      storage_mod = ::AttachmentFu::Backends.const_get("#{options[:storage].to_s.classify}Backend")
      include storage_mod unless included_modules.include?(storage_mod)

      case attachment_options[:processor]
      when :none, nil
        processors = ::AttachmentFu.default_processors.dup
        begin
          if processors.any?
            attachment_options[:processor] = processors.first
            processor_mod = ::AttachmentFu::Processors.const_get("#{attachment_options[:processor].to_s.classify}Processor")
            include processor_mod unless included_modules.include?(processor_mod)
          end
        rescue Object, Exception
          raise unless load_related_exception?($!)

          processors.shift
          retry
        end
      else
        begin
          processor_mod = ::AttachmentFu::Processors.const_get("#{attachment_options[:processor].to_s.classify}Processor")
          include processor_mod unless included_modules.include?(processor_mod)
        rescue Object, Exception
          raise unless load_related_exception?($!)

          puts "Problems loading #{options[:processor]}Processor: #{$!}"
        end
      end unless parent_options[:processor] # Don't let child override processor
    end

    def load_related_exception?(e) #:nodoc: implementation specific
    case
    when e.kind_of?(LoadError), $!.class.name == "CompilationError"
      # We can't rescue CompilationError directly, as it is part of the RubyInline library.
      # We must instead rescue RuntimeError, and check the class' name.
      Rails.logger.info ("An exception was discovered. #{$!}")
      true
    else
      false
    end
    end
    private :load_related_exception?
  end
end