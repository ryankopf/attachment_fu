module AttachmentFu
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
end