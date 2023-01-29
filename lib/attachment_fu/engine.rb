module AttachmentFu
  class Engine < ::Rails::Engine
    #isolate_namespace AttachmentFu
    # Mimic old vendored plugin behavior, attachment_fu/lib is autoloaded.
    #config.autoload_paths << File.expand_path("..", __FILE__)

  end
end