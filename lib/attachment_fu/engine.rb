module AttachmentFu
  class Engine < ::Rails::Engine
    #isolate_namespace AttachmentFu
    # Mimic old vendored plugin behavior, attachment_fu/lib is autoloaded.
    config.autoload_paths << File.expand_path("..", __FILE__)

    initializer "attachment_fu" do
      # require 'geometry'
      # ActiveRecord::Base.send(:extend, AttachmentFu::ActMethods)
      # AttachmentFu.tempfile_path = ATTACHMENT_FU_TEMPFILE_PATH if Object.const_defined?(:ATTACHMENT_FU_TEMPFILE_PATH)
      # FileUtils.mkdir_p AttachmentFu.tempfile_path
    end
  end
end