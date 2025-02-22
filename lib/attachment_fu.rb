require_relative "attachment_fu/version"
require_relative "attachment_fu/engine"
require_relative "attachment_fu/act_methods"
require_relative "attachment_fu/class_methods"
require_relative "attachment_fu/instance_methods"
require_relative "attachment_fu/backends/file_system_backend"
require_relative "attachment_fu/backends/s3_backend"
require_relative "attachment_fu/processors/image_science_processor"
require_relative "attachment_fu/processors/mini_magick_processor"
require_relative "attachment_fu/processors/rmagick_processor"

module AttachmentFu # :nodoc:
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

  ActiveSupport.on_load(:active_record) do
    # self refers to ActiveRecord::Base
    require 'geometry'
    self.send(:extend, AttachmentFu::ActMethods)
    AttachmentFu.tempfile_path = ATTACHMENT_FU_TEMPFILE_PATH if Object.const_defined?(:ATTACHMENT_FU_TEMPFILE_PATH)
    FileUtils.mkdir_p AttachmentFu.tempfile_path
  end

  class ThumbnailError < StandardError;  end
  class AttachmentError < StandardError; end

end
