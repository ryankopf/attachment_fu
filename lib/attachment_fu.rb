require "attachment_fu/version"
require "attachment_fu/engine"
require "attachment_fu/act_methods"
require "attachment_fu/backends/file_system_backend"
require "attachment_fu/backends/s3_backend"
require "attachment_fu/processors/image_science_processor"
require "attachment_fu/processors/mini_magick_processor"
require "attachment_fu/processors/rmagick_processor"



module AttachmentFu # :nodoc:
  ActiveSupport.on_load(:active_record) do
    # self refers to ActiveRecord::Base
    # self.include Antispam::Tools
    require 'geometry'
    self.send(:extend, AttachmentFu::ActMethods)
    AttachmentFu.tempfile_path = ATTACHMENT_FU_TEMPFILE_PATH if Object.const_defined?(:ATTACHMENT_FU_TEMPFILE_PATH)
    FileUtils.mkdir_p AttachmentFu.tempfile_path
  end
  @@default_processors = %w(ImageScience Rmagick MiniMagick)
  # @@tempfile_path      = File.join(Rails.root, 'tmp', 'attachment_fu')
  @@tempfile_path      = File.join('/', 'tmp', 'attachment_fu')
  @@content_types      = [
    'image/jpeg',
    'image/pjpeg',
    'image/jpg',
    'image/gif',
    'image/png',
    'image/x-png',
    'image/jpg',
    'image/x-ms-bmp',
    'image/bmp',
    'image/x-bmp',
    'image/x-bitmap',
    'image/x-xbitmap',
    'image/x-win-bitmap',
    'image/x-windows-bmp',
    'image/ms-bmp',
    'application/bmp',
    'application/x-bmp',
    'application/x-win-bitmap',
    'application/preview',
    'image/jp_',
    'application/jpg',
    'application/x-jpg',
    'image/pipeg',
    'image/vnd.swiftview-jpeg',
    'image/x-xbitmap',
    'application/png',
    'application/x-png',
    'image/gi_',
    'image/x-citrix-pjpeg',
    'application/octet-stream'
  ]
  mattr_reader :content_types, :tempfile_path, :default_processors
  mattr_writer :tempfile_path

  class ThumbnailError < StandardError;  end
  class AttachmentError < StandardError; end

  module ClassMethods
    delegate :content_types, :to => ::AttachmentFu

    # Performs common validations for attachment models.
    def validates_as_attachment
      validates_presence_of :size, :content_type, :filename
      validate              :attachment_attributes_valid?
    end

    # Returns true or false if the given content type is recognized as an image.
    def image?(content_type)
      content_types.include?(content_type)
    end

    def self.extended(base)
      base.class_attribute :attachment_options
      base.before_destroy :destroy_thumbnails
      base.before_validation :set_size_from_temp_path
      base.after_destroy :destroy_file
      base.after_validation :process_attachment
      base.after_save :after_process_attachment
      #if defined?(::ActiveSupport::Callbacks)
      #  base.define_callbacks :after_resize, :after_attachment_saved, :before_thumbnail_saved
      #end
    end

    # Get the thumbnail class, which is the current attachment class by default.
    # Configure this with the :thumbnail_class option.
    def thumbnail_class
      attachment_options[:thumbnail_class] = attachment_options[:thumbnail_class].constantize unless attachment_options[:thumbnail_class].is_a?(Class)
      attachment_options[:thumbnail_class]
    end

    # Copies the given file path to a new tempfile, returning the closed tempfile.
    def copy_to_temp_file(file, temp_base_name)
      Tempfile.new(temp_base_name, ::AttachmentFu.tempfile_path).tap do |tmp|
        tmp.close
        FileUtils.cp file, tmp.path
      end
    end

    # Writes the given data to a new tempfile, returning the closed tempfile.
    def write_to_temp_file(data, temp_base_name)
      Tempfile.new(temp_base_name, ::AttachmentFu.tempfile_path).tap do |tmp|
        tmp.binmode
        tmp.write data
        tmp.close
      end
    end

    def polymorphic_relation_type_column
      return @@_polymorphic_relation_type_column if defined?(@@_polymorphic_relation_type_column)
      # Checked against ActiveRecord 1.15.6 through Edge @ 2009-08-05.
      ref = reflections.values.detect { |r| r.macro == :belongs_to && r.options[:polymorphic] }
      @@_polymorphic_relation_type_column = ref && ref.options[:foreign_type]
    end
  end

  module InstanceMethods
    def self.included(base)
      base.define_callbacks *[:after_resize, :after_attachment_saved, :before_thumbnail_saved] if base.respond_to?(:define_callbacks)
    end

    # Checks whether the attachment's content type is an image content type
    def image?
      self.class.image?(content_type)
    end

    # Returns true/false if an attachment is thumbnailable.  A thumbnailable attachment has an image content type and the parent_id attribute.
    def thumbnailable?
      image? && respond_to?(:parent_id) && parent_id.nil?
    end

    # Returns the class used to create new thumbnails for this attachment.
    def thumbnail_class
      self.class.thumbnail_class
    end

    # Gets the thumbnail name for a filename.  'foo.jpg' becomes 'foo_thumbnail.jpg'
    def thumbnail_name_for(thumbnail = nil)
      if thumbnail.blank?
        if filename.nil?
          return ''
        else
          return filename
        end
      end

      ext = nil
      basename = filename.gsub /\.\w+$/ do |s|
        ext = s; ''
      end
      # ImageScience doesn't create gif thumbnails, only pngs
      ext.sub!(/gif$/i, 'png') if attachment_options[:processor] == "ImageScience"
      "#{basename}_#{thumbnail}#{ext}"
    end

    # Creates or updates the thumbnail for the current attachment.
    def create_or_update_thumbnail(temp_file, file_name_suffix, *size)
      thumbnailable? || raise(ThumbnailError.new("Can't create a thumbnail if the content type is not an image or there is no parent_id column"))
      find_or_initialize_thumbnail(file_name_suffix).tap do |thumb|
        thumb.temp_paths.unshift temp_file
        attributes = {
          :content_type =>             content_type,
          :filename =>                 thumbnail_name_for(file_name_suffix),
          :thumbnail_resize_options => size
        }
        attributes.each{ |a, v| thumb.send "#{a}=", v }
        callback_with_args :before_thumbnail_saved, thumb
        thumb.save
      end
    end

    # Sets the content type.
    def content_type=(new_type)
      write_attribute :content_type, new_type.to_s.strip
    end

    # Sanitizes a filename.
    def filename=(new_name)
      write_attribute :filename, sanitize_filename(new_name)
    end

    # Returns the width/height in a suitable format for the image_tag helper: (100x100)
    def image_size
      [width.to_s, height.to_s] * 'x'
    end

    # Returns true if the attachment data will be written to the storage system on the next save
    def save_attachment?
      File.file?(temp_path.class == String ? temp_path : temp_path.to_filename)
    end

    # nil placeholder in case this field is used in a form.
    def uploaded_data() nil; end

    # This method handles the uploaded file object.  If you set the field name to uploaded_data, you don't need
    # any special code in your controller.
    #
    #   <% form_for :attachment, :html => { :multipart => true } do |f| -%>
    #     <p><%= f.file_field :uploaded_data %></p>
    #     <p><%= submit_tag :Save %>
    #   <% end -%>
    #
    #   @attachment = Attachment.create! params[:attachment]
    #
    def uploaded_data=(file_data)
      if file_data.respond_to?(:content_type)
        return nil if file_data.size == 0
        self.content_type = detect_mimetype(file_data)
        self.filename     = file_data.original_filename if respond_to?(:filename)
      else
        return nil if file_data.blank? || file_data['size'] == 0
        self.content_type = file_data['content_type']
        self.filename =  file_data['filename']
        file_data = file_data['tempfile']
      end
      if file_data.is_a?(StringIO)
        file_data.rewind
        set_temp_data file_data.read
      else
        file_data.respond_to?(:tempfile) ? self.temp_paths.unshift( file_data.tempfile.path ) : self.temp_paths.unshift( file_data.path )
      end
    end

    def detect_mimetype(file_data)
      if file_data.content_type.strip == "application/octet-stream"
        return File.mime_type?(file_data.original_filename)
      else
        return file_data.content_type
      end
    end

    # Gets the latest temp path from the collection of temp paths.  While working with an attachment,
    # multiple Tempfile objects may be created for various processing purposes (resizing, for example).
    # An array of all the tempfile objects is stored so that the Tempfile instance is held on to until
    # it's not needed anymore.  The collection is cleared after saving the attachment.
    def temp_path
      p = temp_paths.first
      p.respond_to?(:path) ? p.path : p.to_s
    end

    # Gets an array of the currently used temp paths.  Defaults to a copy of #full_filename.
    def temp_paths
      @temp_paths ||= (new_record? || !respond_to?(:full_filename) || !File.exist?(full_filename) ?
                         [] : [copy_to_temp_file(full_filename)])
    end

    # Gets the data from the latest temp file.  This will read the file into memory.
    def temp_data
      save_attachment? ? File.read(temp_path) : nil
    end

    # Writes the given data to a Tempfile and adds it to the collection of temp files.
    def set_temp_data(data)
      temp_paths.unshift write_to_temp_file data unless data.nil?
    end

    # Copies the given file to a randomly named Tempfile.
    def copy_to_temp_file(file)
      self.class.copy_to_temp_file file, random_tempfile_filename
    end

    # Writes the given file to a randomly named Tempfile.
    def write_to_temp_file(data)
      self.class.write_to_temp_file data, random_tempfile_filename
    end

    # Stub for creating a temp file from the attachment data.  This should be defined in the backend module.
    def create_temp_file() end

    # Stub for downloading a temp file from the attachment data.  This should be defined in the backend module.
    def download_to_temp_file() end

    # Allows you to work with a processed representation (RMagick, ImageScience, etc) of the attachment in a block.
    #
    #   @attachment.with_image do |img|
    #     self.data = img.thumbnail(100, 100).to_blob
    #   end
    #
    def with_image(&block)
      # Write out the temporary data if it is not present
      if temp_data.nil?
        self.temp_data = current_data
      end
      self.class.with_image(temp_path, &block)
    end

    protected
    # Generates a unique filename for a Tempfile.
    def random_tempfile_filename
      base_filename = filename ? filename.gsub(/\.\w+$/, '') : 'attachment'
      ext = filename ? filename.slice(/\.\w+$/) : ''
      ["#{rand Time.now.to_i}#{base_filename}", ext || '']
    end

    def sanitize_filename(filename)
      return unless filename
      filename.strip.tap do |name|
        # NOTE: File.basename doesn't work right with Windows paths on Unix
        # get only the filename, not the whole path
        name.gsub! /^.*(\\|\/)/, ''

        # Finally, replace all non alphanumeric, underscore or periods with underscore
        name.gsub! /[^A-Za-z0-9\.\-]/, '_'
        # Remove trailing underscore
        name.gsub!(/\_\./, '.')
        # Remove multiple underscores
        name.gsub!(/\_+/, '_')

        # Downcase result including extension
        name.downcase!
        # Shrink the name to a max of 70 characters
        parts = name.split(".")
        parts.first.include?("_thumb") ? parts.first.slice!(82..-1) : parts.first.slice!(70..-1)
        name = parts.join(".")
        return name
      end
    end

    # before_validation callback.
    def set_size_from_temp_path
      self.size = File.size(temp_path) if save_attachment?
    end

    # validates the size and content_type attributes according to the current model's options
    def attachment_attributes_valid?
      [:size, :content_type].each do |attr_name|
        enum = attachment_options[attr_name]
        if Object.const_defined?(:I18n) # Rails >= 2.2
          errors.add attr_name, I18n.translate("activerecord.errors.messages.inclusion", attr_name => enum) unless enum.nil? || enum.include?(send(attr_name))
        else
          errors.add attr_name, ActiveRecord::Errors.default_error_messages[:inclusion] unless enum.nil? || enum.include?(send(attr_name))
        end
      end
    end

    # Initializes a new thumbnail with the given suffix.
    def find_or_initialize_thumbnail(file_name_suffix)
      attrs = {thumbnail: file_name_suffix.to_s}
      attrs[:parent_id] = id if respond_to? :parent_id
      thumb = if thumbnail_class.respond_to?(:where)
                thumbnail_class.where(attrs).first
              else
                thumbnail_class.find(:first, :conditions => attrs)
              end
      unless thumb
        thumb = thumbnail_class.new
        attrs.each{ |a, v| thumb[a] = v }
      end
      thumb
    end

    # Stub for a #process_attachment method in a processor
    def process_attachment_without_processing
      @saved_attachment = save_attachment?
    end

    # Cleans up after processing.  Thumbnails are created, the attachment is stored to the backend, and the temp_paths are cleared.
    def after_process_attachment
      if @saved_attachment
        attachment_attributes_valid?
        return unless self.errors.empty?
        if thumbnailable? && !attachment_options[:thumbnails].blank? && parent_id.nil? #XZ1
          temp_file = temp_path || create_temp_file
          attachment_options[:thumbnails].each { |suffix, size|
            if size.is_a?(Symbol)
              parent_type = polymorphic_parent_type
              next unless parent_type && [parent_type, parent_type.tableize].include?(suffix.to_s) && respond_to?(size)
              size = send(size)
            end
            if size.is_a?(Hash)
              parent_type = polymorphic_parent_type
              next unless parent_type && [parent_type, parent_type.tableize].include?(suffix.to_s)
              size.each { |ppt_suffix, ppt_size|
                thumb = create_or_update_thumbnail(temp_file, ppt_suffix, *ppt_size)
              }
            else
              thumb = create_or_update_thumbnail(temp_file, suffix, *size)
            end
            errors.add(:base,"error saving thumbnail. #{thumb.errors.full_messages}") unless thumb.errors.empty?
          }
        end
        save_to_storage if self.errors.empty?
        @temp_paths.clear
        @saved_attachment = nil
        #callback :after_attachment_saved
        callback_with_args :after_attachment_saved, nil
      end
    end

    # Resizes the given processed img object with either the attachment resize options or the thumbnail resize options.
    def resize_image_or_thumbnail!(img)
      if (!respond_to?(:parent_id) || parent_id.nil?) && attachment_options[:resize_to] # parent image
        resize_image(img, attachment_options[:resize_to])
      elsif thumbnail_resize_options # thumbnail
        resize_image(img, thumbnail_resize_options)
      end
    end

    def callback_with_args(method, arg = self)
      if respond_to?(method)
        send(method, arg)
      end
    end

    # Removes the thumbnails for the attachment, if it has any
    def destroy_thumbnails
      self.thumbnails.each { |thumbnail| thumbnail.destroy } if thumbnailable?
    end

    def polymorphic_parent_type
      rel_name = self.class.polymorphic_relation_type_column
      rel_name && send(rel_name)
    end

    def get_jpeg_quality(require_0_to_100 = true)
      quality = attachment_options[:jpeg_quality]
      if quality.is_a?(Hash)
        sbl_quality  = thumbnail && quality[thumbnail.to_sym]
        sbl_quality  = nil if sbl_quality && require_0_to_100 && !sbl_quality.to_i.between?(0, 100)
        surface      = (width || 1) * (height || 1)
        size_quality = quality.detect { |k, v|
          next unless k.is_a?(String) && k =~ /^(<|>=)(\d+)$/
          op, threshold = $1, $2.to_i
          surface.send(op, threshold)
        }
        quality = sbl_quality || size_quality && size_quality[1]
      end
      return quality && (!require_0_to_100 || quality.to_i.between?(0, 100)) ? quality : nil
    end
  end
end
