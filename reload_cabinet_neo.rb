# encoding: UTF-8
# =============================================================================
# أداة إعادة التحميل السريع — v8
# =============================================================================
# - استخدام Global Variables لإزالة Observers
# - إغلاق FloatingToolbar قبل إعادة التحميل
# - Toolbar ما بيتشالش (منع التكرار)
# =============================================================================

module CabinetNeo
  module Reloader
    PLUGIN_DIR = File.dirname(__FILE__).freeze
    MAIN_FILE  = File.join(PLUGIN_DIR, 'cabinet_neo', 'main.rb').freeze

    def self.reload!
      puts "\n" + ('=' * 60)
      puts '[Cabinet Neo] 🔄 Starting hot reload...'
      puts ('=' * 60)

      kill_dialogs
      kill_floating_toolbar
      kill_observers
      remove_menu_items
      remove_toolbars
      unload_ruby_files
      reset_module_state
      clear_file_loaded_flags
      load_main_file

      puts ('=' * 60)
      puts '[Cabinet Neo] ✅ Hot reload complete.'
      puts ('=' * 60) + "\n"
    rescue StandardError => e
      puts "[Cabinet Neo] ❌ Reload failed: #{e.message}"
      puts e.backtrace.first(15).join("\n")
    end

    # -------------------------------------------------------------------------
    # 1) إغلاق كل النوافذ
    # -------------------------------------------------------------------------
    def self.kill_dialogs
      begin
        if defined?(CabinetNeo::UI::DialogManager)
          dm = CabinetNeo::UI::DialogManager.instance
          dm.dispose if dm.respond_to?(:dispose)
          dm.close if dm.respond_to?(:close) && dm.visible?
        end
      rescue StandardError
      end

      closed = 0
      begin
        ObjectSpace.each_object(Class) do |klass|
          next unless klass.name.to_s.include?('SelectionPopup')
          next unless klass.respond_to?(:instance)
          begin
            inst = klass.instance
            if inst.respond_to?(:dispose)
              inst.dispose
              closed += 1
            end
          rescue StandardError
          end
        end
      rescue StandardError
      end

      puts "  [1/8] 🪟 Closed #{closed} popup instance(s)."
    end

    # -------------------------------------------------------------------------
    # 1.b) إغلاق كل الـ FloatingToolbars
    # -------------------------------------------------------------------------
    def self.kill_floating_toolbar
      closed = 0

      begin
        if defined?($cabinet_neo_ftb_dialog) && $cabinet_neo_ftb_dialog
          begin
            $cabinet_neo_ftb_dialog.close
          rescue StandardError
          end
          $cabinet_neo_ftb_dialog = nil
          closed += 1
        end
      rescue StandardError
      end

      begin
        ObjectSpace.each_object(Class) do |klass|
          next unless klass.name.to_s.include?('FloatingToolbar')
          next unless klass.respond_to?(:instance)
          begin
            inst = klass.instance
            if inst.respond_to?(:hide)
              inst.hide
              closed += 1
            end
          rescue StandardError
          end
        end
      rescue StandardError
      end

      puts "  [1b/8] 🎈 Closed #{closed} floating toolbar(s)."
    end

    # -------------------------------------------------------------------------
    # 2) إزالة كل Observers
    # -------------------------------------------------------------------------
    def self.kill_observers
      model = Sketchup.active_model
      removed_sel = 0

      if defined?($cabinet_neo_sel_observer) && $cabinet_neo_sel_observer
        if model
          begin
            model.selection.remove_observer($cabinet_neo_sel_observer)
            removed_sel += 1
          rescue StandardError
          end
        end
        $cabinet_neo_sel_observer = nil
      end

      if model
        begin
          ObjectSpace.each_object(Sketchup::SelectionObserver) do |obs|
            begin
              model.selection.remove_observer(obs)
              removed_sel += 1
            rescue StandardError
            end
          end
        rescue StandardError
        end
      end

      removed_app = 0
      if defined?($cabinet_neo_app_observer) && $cabinet_neo_app_observer
        begin
          Sketchup.remove_observer($cabinet_neo_app_observer)
          removed_app += 1
        rescue StandardError
        end
        $cabinet_neo_app_observer = nil
      end

      begin
        ObjectSpace.each_object(Sketchup::AppObserver) do |obs|
          next unless obs.class.name.to_s.include?('CabinetNeo')
          begin
            Sketchup.remove_observer(obs)
            removed_app += 1
          rescue StandardError
          end
        end
      rescue StandardError
      end

      puts "  [2/8] 🔌 Removed #{removed_sel} sel + #{removed_app} app observer(s)."
    end

    # -------------------------------------------------------------------------
    # 3) حذف عناصر القائمة
    # -------------------------------------------------------------------------
    def self.remove_menu_items
      plugins_menu = ::UI.menu('Plugins')
      targets = []
      plugins_menu.each do |item|
        next unless item.is_a?(::UI::Command)
        targets << item if item.menu_text.to_s.include?('Cabinet Neo')
      end
      targets.each { |item| plugins_menu.remove_item(item) }
      puts "  [3/8] 📋 Removed #{targets.size} menu item(s)."
    rescue StandardError => e
      puts "  [3/8] ⚠️  Menu cleanup skipped: #{e.message}"
    end

    # -------------------------------------------------------------------------
    # 3.b) تخطي تنظيف الـ Toolbars (منع التكرار)
    # -------------------------------------------------------------------------
    def self.remove_toolbars
      puts "  [3b/8] ⏭️  Skipping toolbar cleanup (prevent duplicates)."
    end

    # -------------------------------------------------------------------------
    # 4) إزالة ملفات الإضافة من cache
    # -------------------------------------------------------------------------
    def self.unload_ruby_files
      pattern = File.join(PLUGIN_DIR, 'cabinet_neo').gsub('\\', '/')
      removed = 0
      $LOADED_FEATURES.reject! do |path|
        normalized = path.gsub('\\', '/')
        if normalized.start_with?(pattern)
          removed += 1
          true
        else
          false
        end
      end
      puts "  [4/8] 🧹 Unloaded #{removed} Ruby file(s) from cache."
    end

    # -------------------------------------------------------------------------
    # 5) إعادة تعيين حالة الوحدة
    # -------------------------------------------------------------------------
    def self.reset_module_state
      protected = [:Reloader]
      CabinetNeo.constants.each do |const|
        next if protected.include?(const)
        CabinetNeo.send(:remove_const, const)
      end
      CabinetNeo.instance_variable_set(:@loader_initialized, false)
      CabinetNeo.instance_variable_set(:@main_initialized, false)
      puts '  [5/8] ♻️  Module state reset.'
    rescue StandardError => e
      puts "  [5/8] ⚠️  Reset warning: #{e.message}"
    end

    # -------------------------------------------------------------------------
    # 6) مسح file_loaded
    # -------------------------------------------------------------------------
    def self.clear_file_loaded_flags
      if defined?($loaded_files) && $loaded_files.is_a?(Array)
        before = $loaded_files.size
        $loaded_files.reject! { |f| f.to_s.include?('cabinet_neo') }
        after = $loaded_files.size
        puts "  [6/8] 🏷️  Cleared #{before - after} file_loaded flag(s)."
      else
        puts '  [6/8] 🏷️  file_loaded flags not accessible.'
      end
    rescue StandardError => e
      puts "  [6/8] ⚠️  file_loaded cleanup skipped: #{e.message}"
    end

    # -------------------------------------------------------------------------
    # 7) تحميل main.rb
    # -------------------------------------------------------------------------
    def self.load_main_file
      load MAIN_FILE
      puts '  [7/8] 📦 main.rb re-executed.'
    rescue StandardError => e
      puts "  [7/8] ❌ main.rb failed: #{e.message}"
      raise e
    end
  end

  def self.reload!
    Reloader.reload!
  end
end

# ⭐ تعريف rl للاستخدام من Console
Object.send(:define_method, :rl) do
  CabinetNeo.reload!
end

CabinetNeo.reload!