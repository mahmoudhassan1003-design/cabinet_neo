# encoding: UTF-8
# =============================================================================
# المنسّق المركزي — v20 (مع إخفاء الشريط العائم عند فتح النافذة)
# =============================================================================

require 'sketchup.rb'

module CabinetNeo

  def self.register_selection_observer
    model = Sketchup.active_model
    return puts('[Cabinet Neo] ⚠️  No active model') unless model

    if defined?($cabinet_neo_sel_observer) && $cabinet_neo_sel_observer
      begin; model.selection.remove_observer($cabinet_neo_sel_observer); rescue StandardError; end
      $cabinet_neo_sel_observer = nil
    end
    begin
      ObjectSpace.each_object(Sketchup::SelectionObserver) do |obs|
        next unless obs.class.name.to_s.include?('CabinetNeo')
        begin; model.selection.remove_observer(obs); rescue StandardError; end
      end
    rescue StandardError
    end
    $cabinet_neo_sel_observer = UI::SelectionObserver.new
    model.selection.add_observer($cabinet_neo_sel_observer)
    puts '[Cabinet Neo] 👁️  Selection observer registered'
  rescue StandardError => e
    puts "[Cabinet Neo] ❌ Observer failed: #{e.message}"
  end

  def self.register_model_observer
    if defined?($cabinet_neo_app_observer) && $cabinet_neo_app_observer
      begin; Sketchup.remove_observer($cabinet_neo_app_observer); rescue StandardError; end
      $cabinet_neo_app_observer = nil
    end
    begin
      ObjectSpace.each_object(Sketchup::AppObserver) do |obs|
        next unless obs.class.name.to_s.include?('CabinetNeo')
        begin; Sketchup.remove_observer(obs); rescue StandardError; end
      end
    rescue StandardError
    end
    $cabinet_neo_app_observer = UI::ModelObserver.new
    Sketchup.add_observer($cabinet_neo_app_observer)
    puts '[Cabinet Neo] 👁️  Model observer registered'
  rescue StandardError => e
    puts "[Cabinet Neo] ❌ Model observer failed: #{e.message}"
  end

  def self.nuke_old_popup_dialogs
    begin
      if defined?(CabinetNeo::UI::SelectionPopup)
        CabinetNeo::UI::SelectionPopup.instance.dispose
      end
    rescue StandardError
    end
  end

  # ⭐ إخفاء الشريط العائم عند فتح النافذة الرئيسية
  def self.show_dialog
    begin
      if defined?(UI::FloatingToolbar) && UI::FloatingToolbar.respond_to?(:instance)
        UI::FloatingToolbar.instance.hide
      end
    rescue StandardError
    end

    UI::DialogManager.instance.show
  rescue StandardError => e
    puts "[Cabinet Neo] Failed to show dialog: #{e.message}"
    ::UI.messagebox("Cabinet Neo failed to open:\n#{e.message}")
  end

  # 🧱 مراقب اللصق: النسخ الملصوقة من الوحدات بتنزل على الأرض
  def self.register_floor_observer
    Geometry::FloorSnap.attach(Sketchup.active_model) if defined?(Geometry::FloorSnap)
  rescue StandardError => e
    puts "[Cabinet Neo] ❌ Floor observer failed: #{e.message}"
  end

  def self.reattach_observer
    register_selection_observer
    register_floor_observer
  rescue StandardError => e
    puts "[Cabinet Neo] Reattach failed: #{e.message}"
  end

  unless defined?(@main_initialized) && @main_initialized
    @main_initialized = true

    require_relative 'version'
    require_relative 'geometry/constants'
    require_relative 'materials/material_library'
    require_relative 'materials/texture_loader'
    require_relative 'materials/style_library'
    require_relative 'materials/ocl_bridge'
    require_relative 'geometry/panel_factory'
    require_relative 'geometry/cabinet_builder'
    require_relative 'geometry/ts_builder'
    require_relative 'geometry/unit_footprint'
    require_relative 'geometry/countertop_builder'
    require_relative 'geometry/unit_arranger'
    require_relative 'geometry/floor_snap'
    require_relative 'tools/sink_tool'
    require_relative 'tools/move_tool'
    require_relative 'ui/sink_popup'
    require_relative 'ui/sink_setup'
    require_relative 'ui/dialog_manager'
    require_relative 'ui/selection_popup'

    ftb_path = File.join(__dir__, 'ui', 'floating_toolbar.rb')
    if File.exist?(ftb_path)
      begin
        load ftb_path
        if defined?(CabinetNeo::UI::FloatingToolbar)
          puts '[Cabinet Neo] ✅ FloatingToolbar OK'
        else
          puts '[Cabinet Neo] ❌ FloatingToolbar constant missing'
        end
      rescue StandardError => e
        puts "[Cabinet Neo] ❌ Load failed: #{e.message}"
      end
    else
      puts '[Cabinet Neo] ❌ floating_toolbar.rb NOT FOUND'
    end

    require_relative 'ui/model_observer'
    require_relative 'commands/launch_command'

    if Sketchup.version.to_i < MIN_SKETCHUP_VERSION
      ::UI.messagebox(
        "Cabinet Neo requires SketchUp 2017 or newer.\nDetected: #{Sketchup.version}"
      )
    else
      Commands::LaunchCommand.register
      nuke_old_popup_dialogs
      register_selection_observer
      register_model_observer
      register_floor_observer

      if defined?(CabinetNeo::UI::FloatingToolbar)
        begin
          UI::FloatingToolbar.instance.send(:close_old_instances) if UI::FloatingToolbar.instance.respond_to?(:close_old_instances, true)
          UI::FloatingToolbar.instance.show
          puts '[Cabinet Neo] 🎈 Floating toolbar shown'
        rescue StandardError => e
          puts "[Cabinet Neo] Floating toolbar failed: #{e.message}"
        end
      end

      puts "[Cabinet Neo] Loaded v#{VERSION} (build #{BUILD})."
    end
  end
end