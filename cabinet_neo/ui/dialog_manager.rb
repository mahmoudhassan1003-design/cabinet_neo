# encoding: UTF-8
# =============================================================================
# مدير النافذة الرئيسية — v22
# (+ tall_oven + اختيار القسم السفلي)
# =============================================================================

require 'sketchup.rb'
require 'json'

module CabinetNeo
  module UI
    class DialogManager
      EXPANDED_WIDTH   = 1280
      EXPANDED_HEIGHT  = 840
      COLLAPSED_HEIGHT = 60
      MIN_WIDTH        = 1024

      DIALOG_OPTIONS = {
        dialog_title:    'Cabinet Neo',
        preferences_key: 'CabinetNeo_MainDialog',
        scrollable:      true,
        resizable:       true,
        width:           EXPANDED_WIDTH,
        height:          EXPANDED_HEIGHT,
        min_width:       MIN_WIDTH,
        min_height:      COLLAPSED_HEIGHT,
        style:           ::UI::HtmlDialog::STYLE_UTILITY
      }.freeze

      class << self
        def instance; @instance ||= new; end
      end

      def initialize
        @dialog = nil
        @collapsed = false
      end

      def show
        if @dialog
          vis = (@dialog.visible? rescue false)
          if vis
            begin
              if @collapsed
                @dialog.set_size(EXPANDED_WIDTH, EXPANDED_HEIGHT)
                @collapsed = false
                send_event('dialog_state', { collapsed: false })
              end
              @dialog.bring_to_front
            rescue StandardError => e
              log_error('show/bring_to_front', e)
            end
            return
          end
          # لسه بيفتح (ضغطة مزدوجة) → تجاهل بدل ما نعمل نافذة تانية
          return if @opened_at && (Time.now - @opened_at) < 2.0
          old = @dialog
          @dialog = nil
          @collapsed = false
          begin; old.close; rescue StandardError; end
        end
        build_dialog
        @opened_at = Time.now
        @dialog.show
      rescue StandardError => e
        log_error('show', e)
        ::UI.messagebox("Cabinet Neo failed to open:\n#{e.message}")
      end

      def close; @dialog.close if @dialog && @dialog.visible?; rescue StandardError; end

      def dispose
        begin; @dialog.close if @dialog && @dialog.respond_to?(:visible?) && @dialog.visible?; rescue StandardError; end
        @dialog = nil; @collapsed = false
      rescue StandardError
      end

      def visible?; @dialog ? @dialog.visible? : false; end

      # want: 'true' = تصغير، 'false' = تكبير، nil = قلب الحالة الحالية
      def toggle_minimize(want = nil)
        puts "[Cabinet Neo] minimize_dialog want=#{want.inspect} collapsed=#{@collapsed}"
        return unless @dialog
        target = want.nil? ? !@collapsed : (want.to_s == 'true')
        @collapsed = target
        height = target ? COLLAPSED_HEIGHT : EXPANDED_HEIGHT
        dlg = @dialog
        apply = lambda do
          begin
            dlg.set_size(EXPANDED_WIDTH, height)
          rescue StandardError => e
            log_error('toggle_minimize/set_size', e)
          end
        end
        apply.call
        # على ويندوز أحيانًا set_size جوه الـ callback بيتجاهل → نعيدها بعد لحظة
        ::UI.start_timer(0.15, false) { apply.call if @dialog.equal?(dlg) }
        send_event('dialog_state', { collapsed: target })
      end

      def toggle_floating_toolbar
        puts '[Cabinet Neo] toggle_floating_toolbar'
        unless defined?(::CabinetNeo::UI::FloatingToolbar)
          ::UI.messagebox('القائمة العائمة غير محمّلة', ::MB_OK, 'Cabinet Neo')
          return
        end
        ftb = ::CabinetNeo::UI::FloatingToolbar.instance
        if ftb.visible?
          ftb.hide
        else
          ftb.show
        end
      rescue StandardError => e
        log_error('toggle_floating_toolbar', e)
      end

      def send_event(event_name, payload = {})
        return unless @dialog && @dialog.visible?
        envelope = { event: event_name.to_s, payload: payload }.to_json
        @dialog.execute_script(
          "window.CabinetNeo && window.CabinetNeo.receive(#{envelope});"
        )
      rescue StandardError => e
        log_error("send_event(#{event_name})", e)
      end

      private

      def build_dialog
        @dialog = ::UI::HtmlDialog.new(DIALOG_OPTIONS)
        register_callbacks
        load_html
        attach_on_closed_hook
      end

      def attach_on_closed_hook
        return unless @dialog.respond_to?(:set_on_closed)
        dlg = @dialog
        dlg.set_on_closed do
          puts '[Cabinet Neo] 🚪 Dialog closed'
          # مانمسحش النافذة الجديدة لو الـ closed بتاع نافذة قديمة جه متأخر
          if @dialog.nil? || @dialog.equal?(dlg)
            @dialog = nil
            @collapsed = false
          end
        end
      rescue StandardError
      end

      def load_html
        html_path = File.join(__dir__, 'html', 'index.html')
        if File.exist?(html_path)
          @dialog.set_file(html_path)
        else
          @dialog.set_html('<h2>Cabinet Neo</h2><p>UI assets missing.</p>')
        end
      end

      def register_callbacks
        add_callback('ui_ready')        { |_c|         on_ui_ready }
        add_callback('close_dialog')    { |_c|         close }
        add_callback('minimize_dialog') { |_c, flag|   toggle_minimize(flag) }
        # القائمة العائمة (+ أسماء بديلة لو الزرار في الواجهة بينادي باسم تاني)
        %w[toggle_floating_toolbar toggle_toolbar toggle_ftb ftb_toggle show_toolbar].each do |nm|
          add_callback(nm) { |_c| toggle_floating_toolbar }
        end
        add_callback('log')             { |_c, msg|    puts "[Cabinet Neo UI] #{msg}" }
        add_callback('notify')          { |_c, t, m|   ::UI.messagebox(m, ::MB_OK, t) }

        # ⭐ v22: نضيف tob (tall_bottom_type) كآخر باراميتر
        add_callback('create_cabinet') do |_c, w, h, d, door, sh, sub,
                                            ovd, ovb, ovv, dh_json,
                                            cwr, cwl, cdr, cdl,
                                            fside, cfw, ffw, tob, tbh, toh, tmh, ts_json|
          on_create_cabinet(w, h, d, door, sh, sub,
                            ovd, ovb, ovv, dh_json,
                            cwr, cwl, cdr, cdl,
                            fside, cfw, ffw, tob, tbh, toh, tmh, ts_json)
        end

        add_callback('save_settings')   { |_c, json|   on_save_settings(json) }
        add_callback('load_settings')   { |_c|         on_load_settings }
        add_callback('ocl_list_materials') { |_c|      on_ocl_list_materials }
        add_callback('ocl_apply')          { |_c, json| on_ocl_apply(json) }
        add_callback('list_styles')   { |_c|          on_list_styles }
        add_callback('apply_style')   { |_c, id|      on_apply_style(id) }
        add_callback('save_style')    { |_c, json|    on_save_style(json) }
        add_callback('delete_style')  { |_c, id|      on_delete_style(id) }
        add_callback('list_available_materials') { |_c| on_list_available_materials }
      end

      def add_callback(name, &block)
        @dialog.add_action_callback(name) do |ctx, *args|
          begin
            block.call(ctx, *args)
          rescue StandardError => e
            log_error("callback:#{name}", e)
          end
        end
      end

      def on_ui_ready
        # النافذة بتفتح دايمًا مكبّرة (الحجم المحفوظ ممكن يكون مصغّر من آخر مرة)
        @collapsed = false
        begin; @dialog.set_size(EXPANDED_WIDTH, EXPANDED_HEIGHT) if @dialog; rescue StandardError; end
        send_event('dialog_state', { collapsed: false })
        send_event('app_booted', {
          version:  CabinetNeo::VERSION,
          build:    CabinetNeo::BUILD,
          sketchup: Sketchup.version,
          settings: read_settings
        })
      end

      # ⭐ v22: نستقبل tall_bottom_type
      def on_create_cabinet(w, h, d, door_type, shelves,
                            unit_subtype = 'standard',
                            oven_drawer = 'none',
                            oven_drawer_box = 'true',
                            oven_vent = 'false',
                            drawer_heights_json = nil,
                            corner_w_right = nil,
                            corner_w_left = nil,
                            corner_d_right = nil,
                            corner_d_left = nil,
                            fixed_side = nil,
                            counter_width = nil,
                            filler_width = nil,
                            tall_bottom_type = nil,
                            tall_bottom_h = nil,
                            tall_oven_h = nil,
                            tall_micro_h = nil,
                            ts_json = nil)

        unit_subtype = (unit_subtype.nil? || unit_subtype.to_s.strip.empty?) ? 'standard' : unit_subtype.to_s
        unit_subtype = 'corner_L' if unit_subtype == 'corner'

        oven_drawer = (oven_drawer.nil? || oven_drawer.to_s.strip.empty?) ? 'none' : oven_drawer.to_s

        oven_box = case oven_drawer_box
                   when false, 'false', '0', 0, nil then false
                   else true
                   end

        oven_vent_bool = case oven_vent
                         when true, 'true', '1', 1 then true
                         else false
                         end

        drawer_heights = parse_drawer_heights(drawer_heights_json)

        params = {
          width: w.to_i, height: h.to_i, depth: d.to_i,
          door_type: door_type.to_s, shelves: shelves.to_i,
          unit_subtype: unit_subtype,
          oven_drawer:  oven_drawer,
          oven_drawer_box: oven_box,
          oven_vent: oven_vent_bool,
          drawer_heights: drawer_heights,
          corner_w_right: corner_w_right ? corner_w_right.to_f : nil,
          corner_w_left:  corner_w_left  ? corner_w_left.to_f  : nil,
          corner_d_right: corner_d_right ? corner_d_right.to_f : nil,
          corner_d_left:  corner_d_left  ? corner_d_left.to_f  : nil,
          fixed_side:    fixed_side    ? fixed_side.to_s       : 'left',
          counter_width: counter_width ? counter_width.to_f    : 500.0,
          filler_width:  filler_width  ? filler_width.to_f     : 150.0,
          tall_bottom_type: (tall_bottom_type || 'drawers').to_s,
          tall_bottom_h:     tall_bottom_h ? tall_bottom_h.to_f : 620.0,
          tall_oven_niche_h: tall_oven_h   ? tall_oven_h.to_f   : 600.0,
          tall_micro_door_h: tall_micro_h  ? tall_micro_h.to_f  : 450.0,
          ts: ::CabinetNeo::Geometry::CabinetBuilder.ts_normalize(ts_json.to_s.strip.empty? ? nil : ts_json)
        }
        puts "[Cabinet Neo] create_cabinet #{params.inspect}"
        begin
          instance = ::CabinetNeo::Geometry::CabinetBuilder.build(params)
          send_event('cabinet_created', params.merge(success: true, name: instance.name))
        rescue StandardError => e
          log_error('create_cabinet', e)
          send_event('cabinet_created', params.merge(success: false, error: e.message))
          ::UI.messagebox("فشل إنشاء الخزانة ❌\n\n#{e.message}", ::MB_OK, 'Cabinet Neo')
        end
      end

      def parse_drawer_heights(json)
        return nil if json.nil? || json.to_s.strip.empty?
        arr = JSON.parse(json.to_s)
        return nil unless arr.is_a?(Array)
        return nil if arr.empty?
        arr.map { |x| x.to_f }
      rescue StandardError => e
        puts "[Cabinet Neo] parse_drawer_heights: #{e.message}"
        nil
      end

      def on_ocl_list_materials
        model = Sketchup.active_model
        list = ::CabinetNeo::Materials::OCLBridge.to_json_list(model)
        send_event('ocl_materials', list)
      rescue StandardError => e
        log_error('ocl_list_materials', e)
      end

      def on_ocl_apply(json)
        data = safe_parse(json)
        mat_name  = data['material']
        part_type = data['part'] || 'all'
        model = Sketchup.active_model

        result = ::CabinetNeo::Materials::OCLBridge.apply_material(model, mat_name, part_type)
        send_event('ocl_applied', {
          success:  result[:ok], reason: result[:reason], count: result[:count],
          material: mat_name, part: part_type
        })
      end

      def on_list_styles
        model = Sketchup.active_model
        list = ::CabinetNeo::Materials::StyleLibrary.to_json_list(model)
        send_event('styles_list', list)
      rescue StandardError => e
        log_error('list_styles', e)
      end

      def on_apply_style(style_id)
        model = Sketchup.active_model
        result = ::CabinetNeo::Materials::StyleLibrary.apply(model, style_id)
        send_event('style_applied', result)
      rescue StandardError => e
        log_error('apply_style', e)
        send_event('style_applied', { success: false, reason: e.message })
      end

      def on_list_available_materials
        model = Sketchup.active_model
        list = ::CabinetNeo::Materials::StyleLibrary.available_materials_for_ui(model)
        send_event('available_materials', list)
      rescue StandardError => e
        log_error('list_available_materials', e)
      end

      def on_save_style(json)
        data = safe_parse(json)
        style_data = {
          id:      data['id'],
          name:    data['name'],
          name_ar: data['name_ar'] || data['name'],
          desc:    data['desc'] || '',
          colors:  data['colors'] || ['#cccccc', '#aaaaaa', '#888888'],
          surface: (data['surface'] || {}).each_with_object({}) do |(k, v), h|
            h[k.to_s.to_sym] = symbolize_inner(v)
          end,
          edges: (data['edges'] || {}).each_with_object({}) do |(k, v), h|
            h[k.to_s.to_sym] = (v || {}).each_with_object({}) do |(fk, fv), fh|
              fh[fk.to_s.to_sym] = fv
            end
          end
        }
        result = ::CabinetNeo::Materials::StyleLibrary.save_custom_style(style_data)
        send_event('style_saved', result)
      rescue StandardError => e
        log_error('save_style', e)
        send_event('style_saved', { success: false, reason: e.message })
      end

      def on_delete_style(style_id)
        result = ::CabinetNeo::Materials::StyleLibrary.delete_custom_style(style_id)
        send_event('style_deleted', result)
      rescue StandardError => e
        log_error('delete_style', e)
        send_event('style_deleted', { success: false, reason: e.message })
      end

      def symbolize_inner(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) { |(k, v), h| h[k.to_s.to_sym] = v }
      end

      def on_save_settings(json)
        settings = safe_parse(json)
        write_settings(settings)
        if defined?(::CabinetNeo::UI::FloatingToolbar)
          ::CabinetNeo::UI::FloatingToolbar.instance.apply_theme(settings['ui'])
        end
        puts "[Cabinet Neo] settings saved"
        send_event('settings_saved', { success: true })
      end

      def on_load_settings
        send_event('settings_loaded', read_settings)
      end

      def settings_file_path
        File.join(__dir__, '..', '..', 'user_settings.json')
      end

      def read_settings
        path = settings_file_path
        return {} unless File.exist?(path)
        raw = File.read(path, encoding: 'UTF-8')
        return {} if raw.strip.empty?
        parsed = JSON.parse(raw)
        parsed.is_a?(Hash) ? parsed : {}
      rescue StandardError => e
        puts "[Cabinet Neo] read_settings: #{e.message}"
        {}
      end

      def write_settings(settings)
        return unless settings.is_a?(Hash)
        path = settings_file_path
        File.write(path, JSON.pretty_generate(settings), encoding: 'UTF-8')
      rescue StandardError => e
        puts "[Cabinet Neo] write_settings: #{e.message}"
      end

      def safe_parse(json)
        return {} if json.nil? || json.to_s.strip.empty?
        JSON.parse(json.to_s)
      rescue JSON::ParserError => e
        log_error('json_parse', e)
        {}
      end

      def log_error(context, exception)
        puts "[Cabinet Neo] ERROR in #{context}: #{exception.message}"
        puts exception.backtrace.first(10).join("\n")
      end
    end
  end
end