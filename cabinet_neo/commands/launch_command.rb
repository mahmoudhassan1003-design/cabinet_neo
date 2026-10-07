# encoding: UTF-8
# =============================================================================
# تسجيل أوامر القائمة والـ Toolbar — v7
# شريط واحد "Cabinet Neo" فيه زرارين بأيقونات:
#   1) فتح الإضافة          2) إظهار/إخفاء الشريط العائم (عليه علامة لما يكون ظاهر)
# =============================================================================

require 'sketchup.rb'

module CabinetNeo
  module Commands
    module LaunchCommand
      TOOLBAR_NAME = 'Cabinet Neo'.freeze
      MENU_LABEL   = 'Cabinet Neo'.freeze

      def self.register
        if $cabinet_neo_toolbar_registered == true
          puts '[Cabinet Neo] ⏭️  Toolbar already registered — skipping'
          return
        end
        return if file_loaded?(__FILE__)

        launch_cmd = build_command
        toggle_cmd = floating_toolbar_available? ? build_toolbar_toggle_command : nil

        menu = ::UI.menu('Plugins')
        menu.add_item(launch_cmd)
        menu.add_item(toggle_cmd) if toggle_cmd

        toolbar = ::UI::Toolbar.new(TOOLBAR_NAME)
        toolbar.add_item(launch_cmd)
        toolbar.add_item(toggle_cmd) if toggle_cmd
        toolbar.show
        $cabinet_neo_main_toolbar = toolbar

        file_loaded(__FILE__)
        $cabinet_neo_toolbar_registered = true
      rescue StandardError => e
        puts "[Cabinet Neo] LaunchCommand.register: #{e.message}"
      end

      def self.cleanup_toolbars
      rescue StandardError
      end

      def self.floating_toolbar_available?
        defined?(CabinetNeo::UI::FloatingToolbar) &&
          CabinetNeo::UI::FloatingToolbar.respond_to?(:instance)
      rescue StandardError
        false
      end

      def self.build_command
        cmd = ::UI::Command.new(MENU_LABEL) do
          CabinetNeo.show_dialog
        end
        cmd.tooltip         = 'Cabinet Neo — فتح الإضافة'
        cmd.status_bar_text = 'فتح مصمّم مطابخ Cabinet Neo'
        cmd.menu_text       = MENU_LABEL
        apply_icons(cmd, 'cabinet_neo_16.png', 'cabinet_neo_24.png')
        cmd
      end

      def self.build_toolbar_toggle_command
        cmd = ::UI::Command.new('شريط Cabinet Neo العائم') do
          begin
            CabinetNeo::UI::FloatingToolbar.instance.toggle
          rescue StandardError => e
            puts "[Cabinet Neo] Toggle toolbar failed: #{e.message}"
            ::UI.messagebox("تعذّر فتح الشريط العائم:\n#{e.message}")
          end
        end
        cmd.tooltip         = 'إظهار/إخفاء الشريط العائم'
        cmd.status_bar_text = 'عرض أو إخفاء شريط Cabinet Neo العائم'
        cmd.menu_text       = 'الشريط العائم'
        apply_icons(cmd, 'cabinet_neo_bar_16.png', 'cabinet_neo_bar_24.png')
        cmd.set_validation_proc do
          begin
            CabinetNeo::UI::FloatingToolbar.instance.visible? ? ::MF_CHECKED : ::MF_UNCHECKED
          rescue StandardError
            ::MF_ENABLED
          end
        end
        cmd
      end

      def self.apply_icons(cmd, small, large)
        s = resolve_icon(small)
        l = resolve_icon(large)
        cmd.small_icon = s if s
        cmd.large_icon = l if l
      end

      def self.resolve_icon(filename)
        candidate = File.expand_path(File.join(__dir__, '..', 'icons', filename))
        File.exist?(candidate) ? candidate : nil
      rescue StandardError
        nil
      end
    end
  end
end
