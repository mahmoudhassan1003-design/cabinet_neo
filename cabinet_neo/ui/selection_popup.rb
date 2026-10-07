# encoding: UTF-8
# =============================================================================
# نافذة منبثقة للتحكم بالوحدة — v31
# (+ tall_oven + اختيار القسم السفلي + حقل تعديل رقم الوحدة + حقول ديناميكية)
# =============================================================================

require 'sketchup.rb'
require 'json'

module CabinetNeo
  module UI
    class UnitInstanceObserver < Sketchup::InstanceObserver
      def initialize(popup)
        super()
        @popup = popup
      end

      def onDeleteEntity(_entity)
        begin
          @popup.hide if @popup.respond_to?(:hide)
        rescue StandardError
        end
      end

      def onOpen(_entity); end
      def onClose(_entity); end
    end

    class SelectionPopup
      DIALOG_OPTIONS = {
        dialog_title:    'Cabinet Neo - تحكم',
        preferences_key: 'CabinetNeo_Popup',
        scrollable:      true,
        resizable:       true,
        width:           480,
        height:          780,
        min_width:       460,
        min_height:      500,
        style:           ::UI::HtmlDialog::STYLE_DIALOG
      }.freeze

      CATEGORY_LABELS = {
        'lower' => 'السفلي', 'upper' => 'العلوي',
        'wardrobe' => 'الدواليب', 'balcony' => 'البلكونة'
      }.freeze

      class << self
        def instance; @instance ||= new; end
        def is_showing?; @is_showing == true; end
        def set_showing(val); @is_showing = val; end
      end

      def initialize
        @dialog = nil
        @current_instance = nil
        @suppress_next_selection_event = false
        @instance_observer = nil
      end

      def toggle_for_selection
        if visible?; hide; return; end
        model = Sketchup.active_model
        sel = model.selection.first
        unless sel.is_a?(Sketchup::ComponentInstance) &&
               sel.definition.get_attribute('CabinetNeo', 'generated', false) &&
               sel.definition.name.to_s =~ /^وحدة/
          ::UI.messagebox("الرجاء تحديد وحدة أولاً.", ::MB_OK, 'Cabinet Neo')
          return
        end
        show(sel)
      end

      def show(instance)
        return if @suppress_next_selection_event
        return unless valid_unit?(instance)
        return if SelectionPopup.is_showing?

        SelectionPopup.set_showing(true)
        begin
          @current_instance = instance
          attach_instance_observer(instance)
          if @dialog
            begin
              @dialog.show unless @dialog.visible?
              @dialog.bring_to_front
            rescue StandardError
              @dialog = nil
              build_dialog
              @dialog.show
            end
          else
            build_dialog
            @dialog.show
          end
          push_current_data
        ensure
          SelectionPopup.set_showing(false)
        end
      rescue StandardError => e
        puts "[Cabinet Neo Popup] show error: #{e.message}"
        SelectionPopup.set_showing(false)
      end

      def hide
        detach_instance_observer
        return unless @dialog
        begin; @dialog.close if @dialog.visible?; rescue StandardError; end
      rescue StandardError
      end

      def reset; @current_instance = nil; rescue StandardError; end

      def dispose
        detach_instance_observer
        return unless @dialog
        begin; @dialog.close if @dialog.respond_to?(:visible?) && @dialog.visible?; rescue StandardError; end
        @dialog = nil
        @current_instance = nil
      rescue StandardError
      end

      def visible?
        return false unless @dialog
        @dialog.visible? == true
      rescue StandardError
        false
      end

      private

      def attach_instance_observer(instance)
        detach_instance_observer
        return unless instance && instance.valid?
        begin
          @instance_observer = UnitInstanceObserver.new(self)
          instance.add_observer(@instance_observer)
        rescue StandardError => e
          puts "[Cabinet Neo Popup] observer attach failed: #{e.message}"
        end
      end

      def detach_instance_observer
        return unless @instance_observer
        begin
          if @current_instance && @current_instance.valid?
            @current_instance.remove_observer(@instance_observer)
          end
        rescue StandardError
        end
        @instance_observer = nil
      end

      def valid_unit?(entity)
        return false unless entity.is_a?(Sketchup::ComponentInstance)
        return false unless entity.valid?
        defn = entity.definition
        return false unless defn.get_attribute('CabinetNeo', 'generated', false)
        defn.name.to_s =~ /^وحدة/ ? true : false
      rescue StandardError
        false
      end

      def build_dialog
        @dialog = ::UI::HtmlDialog.new(DIALOG_OPTIONS)
        register_callbacks
        @dialog.set_html(popup_html)
        attach_on_closed_hook
      end

      def attach_on_closed_hook
        return unless @dialog.respond_to?(:set_on_closed)
        dlg = @dialog
        dlg.set_on_closed do
          if @dialog.nil? || @dialog.equal?(dlg)
            @dialog = nil
            @current_instance = nil
          end
        end
      rescue StandardError
      end

      def register_callbacks
        @dialog.add_action_callback('cnp_ready')                  { |_c|        on_popup_ready }
        @dialog.add_action_callback('cnp_apply')                  { |_c, json|  on_apply(json) }
        @dialog.add_action_callback('cnp_open')                   { |_c|        on_open_doors }
        @dialog.add_action_callback('cnp_close_doors')            { |_c|        on_close_doors }
        @dialog.add_action_callback('cnp_delete')                 { |_c|        on_delete_unit }
        @dialog.add_action_callback('cnp_close_popup')            { |_c|        hide }
        @dialog.add_action_callback('cnp_log')                    { |_c, msg|   puts "[Popup JS] #{msg}" }
        @dialog.add_action_callback('cnp_load_materials')         { |_c|        on_load_materials }
        @dialog.add_action_callback('cnp_apply_materials')        { |_c, json|  on_apply_materials(json) }
        @dialog.add_action_callback('cnp_apply_materials_to_cat') { |_c, json|  on_apply_materials_to_cat(json) }
        @dialog.add_action_callback('cnp_set_category')           { |_c, cat|   on_set_category(cat) }
        @dialog.add_action_callback('cnp_set_unit_number')        { |_c, num|   on_set_unit_number(num) }
      end

      def on_popup_ready
        push_current_data
        on_load_materials
      end

      def door_type_for_label(dc)
        swing = dc['door_swing'].to_s
        case swing
        when 'right', 'left' then 'single'
        else 'double'
        end
      end

      def push_current_data
        return unless @dialog
        instance = resolve_instance
        return unless instance
        @current_instance = instance
        dc = instance.definition.attribute_dictionary('dynamic_attributes', false) || {}
        defn = instance.definition

        dh_json = defn.get_attribute('CabinetNeo', 'drawer_heights', nil)
        drawer_heights = begin
          dh_json ? JSON.parse(dh_json) : []
        rescue StandardError
          []
        end

        dbd_json = defn.get_attribute('CabinetNeo', 'drawer_box_depths', nil)
        drawer_box_depths = begin
          dbd_json ? JSON.parse(dbd_json) : []
        rescue StandardError
          []
        end

        subtype_attr = defn.get_attribute('CabinetNeo', 'unit_subtype', 'standard').to_s
        is_sink_unit = defn.get_attribute('CabinetNeo', 'cn_sink_unit', false)
        subtype_attr = 'sink' if is_sink_unit

        unit_number = defn.get_attribute('CabinetNeo', 'unit_number', nil)
        unit_number = instance.name[/\d+/].to_i if unit_number.nil? || unit_number.to_i <= 0

        preview_base = 'file:///' + File.join(__dir__, 'html', 'images', 'units').gsub('\\', '/') + '/'

        data = {
          name:               instance.name,
          unit_number:        unit_number,
          width:              to_cm(dc['lenx']),
          height:             to_cm(dc['body_h']),
          depth:              to_cm(dc['leny']),
          door_swing:         dc['door_swing']  || 'double',
          shelf_count:        dc['shelf_count'] || '1',
          unit_category:      defn.get_attribute('CabinetNeo', 'unit_category', 'lower'),
          unit_subtype:       subtype_attr,
          drawer_heights:     drawer_heights,
          drawer_box_depths:  drawer_box_depths.map { |v| (v.to_f / 10).round(1) },
          mat_door:           defn.get_attribute('CabinetNeo', 'mat_door', ''),
          mat_door_edge:      defn.get_attribute('CabinetNeo', 'mat_door_edge', ''),
          mat_carcass:        defn.get_attribute('CabinetNeo', 'mat_carcass', ''),
          mat_carcass_edge:   defn.get_attribute('CabinetNeo', 'mat_carcass_edge', ''),
          corner_w_right:     defn.get_attribute('CabinetNeo', 'corner_w_right', nil),
          corner_w_left:      defn.get_attribute('CabinetNeo', 'corner_w_left',  nil),
          corner_d_right:     defn.get_attribute('CabinetNeo', 'corner_d_right', nil),
          corner_d_left:      defn.get_attribute('CabinetNeo', 'corner_d_left',  nil),
          fixed_side:         defn.get_attribute('CabinetNeo', 'fixed_side',    'left'),
          counter_width:      defn.get_attribute('CabinetNeo', 'counter_width', 500.0),
          filler_width:       defn.get_attribute('CabinetNeo', 'filler_width',  150.0),
          tall_bottom_type:   defn.get_attribute('CabinetNeo', 'tall_bottom_type', 'drawers'),
          tall_bottom_h:      defn.get_attribute('CabinetNeo', 'tall_bottom_h', 620.0),
          tall_oven_h:        defn.get_attribute('CabinetNeo', 'tall_oven_niche_h', 600.0),
          tall_micro_h:       defn.get_attribute('CabinetNeo', 'tall_micro_door_h', 450.0),
          ts:                 (JSON.parse(defn.get_attribute('CabinetNeo', 'ts_params', '{}').to_s) rescue {}),
          preview_base:       preview_base
        }

        @dialog.execute_script(
          "window.CabinetNeoPopup && window.CabinetNeoPopup.receive(#{data.to_json});"
        )
      rescue StandardError => e
        puts "[Popup] push error: #{e.message}"
      end

      def to_cm(val)
        return 60 if val.nil?
        (val.to_f / 10).round
      end

      def on_load_materials
        return unless @dialog
        model = Sketchup.active_model
        list = ::CabinetNeo::Materials::OCLBridge.to_json_list(model)
        payload = { boards: list[:panels] || [], edges: list[:edges] || [] }
        @dialog.execute_script(
          "window.CabinetNeoPopup && window.CabinetNeoPopup.receiveMaterials(#{payload.to_json});"
        )
      rescue StandardError => e
        puts "[Popup] load_materials error: #{e.message}"
      end

      def on_apply_materials(json)
        data = parse_json(json)
        instance = resolve_instance
        return unless instance

        model = Sketchup.active_model
        model.start_operation('تطبيق الخامات', true)
        begin
          apply_materials_to_units([instance], data)
          save_material_prefs(instance, data)
          model.commit_operation
          model.active_view.invalidate
          push_current_data
          flash_status('ok', 'تم تطبيق الخامات على الوحدة')
        rescue StandardError => e
          model.abort_operation
          puts "[Popup] apply_materials error: #{e.message}"
          flash_status('err', e.message)
        end
      end

      def on_apply_materials_to_cat(json)
        data = parse_json(json)
        cat  = data['category'].to_s
        return if cat.empty?

        model = Sketchup.active_model
        units = []
        model.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance)
          next unless ent.definition.get_attribute('CabinetNeo', 'generated', false)
          next unless ent.definition.name.to_s =~ /^وحدة/
          next unless ent.definition.get_attribute('CabinetNeo', 'unit_category', 'lower').to_s == cat
          units << ent
        end

        label = CATEGORY_LABELS[cat] || cat

        if units.empty?
          flash_status('err', "لا توجد وحدات من نوع #{label}")
          return
        end

        model.start_operation("تطبيق على #{label}", true)
        begin
          apply_materials_to_units(units, data)
          units.each { |u| save_material_prefs(u, data) }
          model.commit_operation
          model.active_view.invalidate
          flash_status('ok', "تم تطبيق على #{units.size} وحدة من #{label}")
        rescue StandardError => e
          model.abort_operation
          puts "[Popup] apply_to_cat error: #{e.message}"
          flash_status('err', e.message)
        end
      end

      def on_set_category(cat)
        instance = resolve_instance
        return unless instance
        cat = cat.to_s
        return unless %w[lower upper wardrobe balcony].include?(cat)

        instance.definition.set_attribute('CabinetNeo', 'unit_category', cat)
        ::CabinetNeo::Geometry::CabinetBuilder.assign_unit_tag(instance, cat)
      rescue StandardError => e
        puts "[Popup] set_category error: #{e.message}"
      end

      def on_set_unit_number(new_num)
        instance = resolve_instance
        return unless instance
        new_num = new_num.to_i
        return if new_num <= 0

        model = Sketchup.active_model
        old_num = instance.definition.get_attribute('CabinetNeo', 'unit_number', nil)
        old_num = instance.name[/\d+/].to_i if old_num.nil? || old_num.to_i <= 0
        return if old_num == new_num

        model.start_operation('تعديل رقم الوحدة', true)
        begin
          ::CabinetNeo::Geometry::CabinetBuilder.rename_unit_number(instance, old_num, new_num)
          current_next = model.get_attribute('CabinetNeo', 'next_unit_number', 1).to_i
          model.set_attribute('CabinetNeo', 'next_unit_number', [current_next, new_num + 1].max)
          model.commit_operation
          model.active_view.invalidate
          push_current_data
          flash_status('ok', "تم تعديل الرقم إلى #{new_num}")
        rescue StandardError => e
          model.abort_operation
          flash_status('err', e.message)
        end
      end

      def apply_materials_to_units(units, data)
        model        = Sketchup.active_model
        style_lib    = ::CabinetNeo::Materials::StyleLibrary
        door_mat     = data['door_mat'].to_s
        door_edge    = data['door_edge'].to_s
        carcass_mat  = data['carcass_mat'].to_s
        carcass_edge = data['carcass_edge'].to_s

        units.each do |unit|
          unit.definition.entities.each do |ent|
            next unless ent.is_a?(Sketchup::ComponentInstance)
            next unless ent.definition.get_attribute('CabinetNeo', 'generated', false)

            piece_key = style_lib.classify_piece(ent)
            next unless piece_key

            next if piece_key == :plinth || piece_key == :handle

            mat_name, edge_name = case piece_key
                                  when :door then [door_mat, door_edge]
                                  else            [carcass_mat, carcass_edge]
                                  end
            next if mat_name.to_s.empty?

            mat = model.materials[mat_name]
            if mat
              ent.definition.entities.grep(Sketchup::Face).each do |f|
                bb = f.bounds
                dims = [bb.width.to_mm.round(1), bb.depth.to_mm.round(1), bb.height.to_mm.round(1)].sort
                next if (dims[1] - 18.0).abs < 3.0
                f.material      = mat
                f.back_material = mat
              end
            end

            next if edge_name.to_s.empty?
            edge_cfg = edge_config_for(piece_key, edge_name)
            style_lib.apply_edges_to_piece(ent, edge_cfg, model)
          end
        end
        units.size
      end

      def save_material_prefs(unit, data)
        defn = unit.definition
        defn.set_attribute('CabinetNeo', 'mat_door',         data['door_mat'].to_s)
        defn.set_attribute('CabinetNeo', 'mat_door_edge',    data['door_edge'].to_s)
        defn.set_attribute('CabinetNeo', 'mat_carcass',      data['carcass_mat'].to_s)
        defn.set_attribute('CabinetNeo', 'mat_carcass_edge', data['carcass_edge'].to_s)
      rescue StandardError
      end

      def edge_config_for(piece_key, edge_name)
        case piece_key
        when :door
          { left: edge_name, right: edge_name, top: edge_name, bottom: edge_name }
        when :floor
          { front: edge_name, back: 'مفحار1', left: edge_name, right: edge_name }
        when :side
          { front: edge_name, back: 'مفحار1', top: edge_name }
        when :shelf
          { front: edge_name }
        when :front_rail
          { front: edge_name, back: edge_name }
        when :back_rail
          { top: edge_name }
        else
          {}
        end
      end

      def flash_status(kind, msg)
        return unless @dialog
        safe = msg.to_s.gsub("'", "\\\\'")
        @dialog.execute_script(
          "window.CabinetNeoPopup && window.CabinetNeoPopup.flashStatus('#{kind}','#{safe}');"
        )
      rescue StandardError
      end

      def on_apply(json)
        data = parse_json(json)
        instance = resolve_instance
        return unless instance

        original_name = instance.name
        original_transform = Geom::Transformation.new(instance.transformation.to_a)

        w       = (data['width']  || 60).to_f * 10
        h       = (data['height'] || 78).to_f * 10
        d       = (data['depth']  || 58).to_f * 10
        swing   = (data['door_swing'] || 'double').to_s
        shelves = (data['shelves'] || 1).to_i
        cat     = (data['unit_category'] || 'lower').to_s

        subtype            = (data['unit_subtype'] || 'standard').to_s
        drawer_heights     = data['drawer_heights'] || [230, 230, 230]
        drawer_box_depths  = data['drawer_box_depths'] || [450, 450, 450]
        tall_bottom        = (data['tall_bottom_type'] || 'drawers').to_s
        tall_bottom_h      = (data['tall_bottom_h'] || 620).to_f
        tall_oven_h        = (data['tall_oven_h']   || 600).to_f
        tall_micro_h       = (data['tall_micro_h']  || 450).to_f
        ts_data            = data['ts']

        cwr = data['corner_w_right']
        cwl = data['corner_w_left']
        cdr = data['corner_d_right']
        cdl = data['corner_d_left']

        cf_side = (data['fixed_side'] || 'left').to_s
        cf_w    = (data['counter_width'] || 500).to_f
        cf_f    = (data['filler_width']  || 150).to_f

        subtype = 'corner_L' if subtype == 'corner'

        old_def_is_sink = instance.definition.get_attribute('CabinetNeo', 'cn_sink_unit', false)
        subtype = 'sink' if old_def_is_sink

        door_type = case swing
                    when 'right' then 'single_right'
                    when 'left'  then 'single_left'
                    else              'double'
                    end

        old_def = instance.definition
        saved_mats = {
          mat_door:         old_def.get_attribute('CabinetNeo', 'mat_door', nil),
          mat_door_edge:    old_def.get_attribute('CabinetNeo', 'mat_door_edge', nil),
          mat_carcass:      old_def.get_attribute('CabinetNeo', 'mat_carcass', nil),
          mat_carcass_edge: old_def.get_attribute('CabinetNeo', 'mat_carcass_edge', nil)
        }
        saved_num = old_def.get_attribute('CabinetNeo', 'unit_number', nil)

        model = Sketchup.active_model
        @suppress_next_selection_event = true

        model.start_operation('تحديث الوحدة', true)
        begin
          detach_instance_observer
          begin; instance.erase! if instance.valid?; rescue StandardError; end

          new_inst = ::CabinetNeo::Geometry::CabinetBuilder.build({
            width: w.to_i, height: h.to_i, depth: d.to_i,
            door_type: door_type, shelves: shelves,
            unit_category: cat,
            unit_subtype: subtype,
            drawer_heights: drawer_heights,
            drawer_box_depths: drawer_box_depths,
            tall_bottom_type: tall_bottom,
            tall_bottom_h:     tall_bottom_h,
            tall_oven_niche_h: tall_oven_h,
            tall_micro_door_h: tall_micro_h,
            ts: ts_data,
            corner_w_right: cwr,
            corner_w_left:  cwl,
            corner_d_right: cdr,
            corner_d_left:  cdl,
            fixed_side:    cf_side,
            counter_width: cf_w,
            filler_width:  cf_f,
            skip_zoom: true, skip_purge: true, custom_name: original_name
          })

          new_inst.transformation = original_transform
          new_inst.name = original_name
          new_inst.definition.set_attribute('CabinetNeo', 'unit_category', cat)
          new_inst.definition.set_attribute('CabinetNeo', 'unit_subtype', subtype)
          new_inst.definition.set_attribute('CabinetNeo', 'cn_sink_unit', subtype == 'sink')
          new_inst.definition.set_attribute('CabinetNeo', 'unit_number', saved_num) if saved_num
          new_inst.definition.set_attribute('CabinetNeo', 'tall_bottom_type', tall_bottom)

          if subtype == 'corner_L'
            new_inst.definition.set_attribute('CabinetNeo', 'corner_w_right', cwr.to_f) if cwr
            new_inst.definition.set_attribute('CabinetNeo', 'corner_w_left',  cwl.to_f) if cwl
            new_inst.definition.set_attribute('CabinetNeo', 'corner_d_right', cdr.to_f) if cdr
            new_inst.definition.set_attribute('CabinetNeo', 'corner_d_left',  cdl.to_f) if cdl
          end

          if subtype == 'counter_fixed'
            new_inst.definition.set_attribute('CabinetNeo', 'fixed_side',    cf_side)
            new_inst.definition.set_attribute('CabinetNeo', 'counter_width', cf_w)
            new_inst.definition.set_attribute('CabinetNeo', 'filler_width',  cf_f)
          end

          ::CabinetNeo::Geometry::CabinetBuilder.assign_unit_tag(new_inst, cat)

          saved_mats.each do |k, v|
            new_inst.definition.set_attribute('CabinetNeo', k.to_s, v) if v
          end

          model.selection.clear
          model.selection.add(new_inst)
          model.commit_operation

          @current_instance = new_inst
          attach_instance_observer(new_inst)
          push_current_data
        rescue StandardError => e
          model.abort_operation
          puts "[Popup] فشل: #{e.message}"
        ensure
          @suppress_next_selection_event = false
        end
      end

      def resolve_instance
        if @current_instance && @current_instance.valid?
          return @current_instance
        end
        model = Sketchup.active_model
        sel = model.selection.first
        return sel if valid_unit?(sel)
        nil
      end

      def parse_json(str)
        return {} if str.nil? || str.to_s.strip.empty?
        JSON.parse(str.to_s)
      rescue JSON::ParserError
        {}
      end

      def on_open_doors
        instance = resolve_instance
        return unless instance
        model = Sketchup.active_model
        @suppress_next_selection_event = true
        model.selection.clear
        model.selection.add(instance)
        @suppress_next_selection_event = false
        ::CabinetNeo::Geometry::CabinetBuilder.open_doors
      end

      def on_close_doors
        instance = resolve_instance
        return unless instance
        model = Sketchup.active_model
        @suppress_next_selection_event = true
        model.selection.clear
        model.selection.add(instance)
        @suppress_next_selection_event = false
        ::CabinetNeo::Geometry::CabinetBuilder.close_doors
      end

      def on_delete_unit
        instance = resolve_instance
        return unless instance
        model = Sketchup.active_model
        @suppress_next_selection_event = true
        detach_instance_observer
        begin
          model.start_operation('حذف الوحدة', true)
          instance.erase!
          model.commit_operation
        rescue StandardError
          model.abort_operation
        ensure
          @suppress_next_selection_event = false
          @current_instance = nil
        end
        hide
      end

      def suppress_next?; @suppress_next_selection_event; end

      def popup_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="ar" dir="rtl">
          <head>
          <meta charset="UTF-8">
          <style>
            :root{
              --bg:#0b0e13;--card:#171c25;--input:#0e1218;
              --border:#232a35;--border-2:#2d3644;
              --text:#e6e9ee;--text-2:#9aa3b1;--text-3:#6b7382;
              --accent:#ff6b1a;--accent-2:#ff8c42;--danger:#ef4444;
            }
            *{box-sizing:border-box;}
            html,body{margin:0;height:100%;background:var(--bg);color:var(--text);
              font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;font-size:13px;
              user-select:none;overflow:hidden;}
            ::-webkit-scrollbar{width:6px;}
            ::-webkit-scrollbar-thumb{background:#2a323e;border-radius:3px;}
            .wrap{padding:12px;display:flex;flex-direction:column;height:100vh;gap:8px;}

            .header{display:flex;align-items:center;justify-content:space-between;
              padding-bottom:8px;border-bottom:1px solid var(--border);flex-shrink:0;}
            .title{display:flex;align-items:center;gap:8px;font-size:13px;
              font-weight:700;color:var(--accent);}
            .title .name{font-size:11.5px;color:var(--text-2);font-weight:500;
              padding-inline-start:6px;}
            .close-x{width:24px;height:24px;border:0;background:transparent;
              color:var(--text-3);cursor:pointer;border-radius:5px;font-size:14px;}
            .close-x:hover{background:#1a2029;color:var(--text);}

            .main-area{flex:1;display:flex;gap:10px;overflow:hidden;min-height:0;}
            .side-preview{flex-shrink:0;width:92px;display:flex;
              flex-direction:column;gap:6px;}

            .unit-preview{width:92px;height:92px;
              display:flex;align-items:center;justify-content:center;
              padding:4px;background:var(--card);
              border:1px solid var(--border);border-radius:8px;overflow:hidden;}
            .unit-preview img{max-width:100%;max-height:100%;
              object-fit:contain;
              filter:drop-shadow(0 2px 5px rgba(0,0,0,.35));}

            .type-badge{font-size:10px;color:var(--text-3);text-align:center;
              padding:5px 4px;background:var(--card);border:1px solid var(--border);
              border-radius:6px;line-height:1.35;font-weight:600;}
            .type-badge b{display:block;color:var(--accent);font-size:10.5px;
              margin-bottom:2px;}

            .content-area{flex:1;display:flex;flex-direction:column;
              gap:8px;overflow:hidden;min-width:0;min-height:0;}

            .tabs{display:flex;gap:4px;background:var(--card);
              border:1px solid var(--border);border-radius:8px;padding:4px;flex-shrink:0;}
            .tab-btn{flex:1;padding:8px 4px;background:transparent;border:0;
              border-radius:6px;color:var(--text-2);cursor:pointer;
              font-family:inherit;font-size:11px;font-weight:600;
              display:flex;align-items:center;justify-content:center;gap:4px;
              transition:.15s;}
            .tab-btn:hover{color:var(--text);background:#1a2029;}
            .tab-btn.active{background:linear-gradient(180deg,var(--accent-2),var(--accent));
              color:#fff;box-shadow:0 2px 6px rgba(255,107,26,.3);}

            .panes{flex:1;overflow-y:auto;display:flex;flex-direction:column;min-height:0;}
            .pane{display:none;flex-direction:column;gap:9px;}
            .pane.active{display:flex;}

            .section{background:var(--card);border:1px solid var(--border);
              border-radius:8px;padding:12px;}
            .section-title{font-size:11.5px;font-weight:700;color:var(--text-2);
              margin-bottom:10px;padding-bottom:6px;border-bottom:1px solid var(--border);
              text-transform:uppercase;letter-spacing:.5px;}
            .section-title.accent{color:var(--accent);border-bottom-color:rgba(255,107,26,.35);
              margin-top:12px;}

            .field{display:flex;flex-direction:column;gap:4px;margin-bottom:9px;}
            .field:last-child{margin-bottom:0;}
            .field-label{font-size:11px;color:var(--text-2);
              display:flex;justify-content:space-between;}
            .field-label .unit{color:var(--text-3);font-size:10px;}
            .ctrl{display:flex;align-items:center;background:var(--input);
              border:1px solid var(--border-2);border-radius:5px;height:34px;padding:0 8px;}
            .ctrl:focus-within{border-color:var(--accent);}
            .ctrl input{flex:1;background:transparent;border:0;outline:0;
              color:var(--text);font-size:13px;font-weight:700;text-align:center;
              -moz-appearance:textfield;}
            .ctrl input::-webkit-inner-spin-button,
            .ctrl input::-webkit-outer-spin-button{-webkit-appearance:none;}
            .ctrl select{flex:1;background:transparent;border:0;outline:0;
              color:var(--text);font-size:12px;font-family:inherit;
              padding:0 4px;cursor:pointer;appearance:none;-webkit-appearance:none;}
            .ctrl select option{background:#1a2029;color:#e6e9ee;}

            .door-row{display:grid;grid-template-columns:repeat(3,1fr);gap:5px;}
            .cat-row{display:grid;grid-template-columns:repeat(4,1fr);gap:5px;}
            .sub-row{display:grid;grid-template-columns:repeat(3,1fr);gap:5px;}
            .tob-row,.tsl-row,.tsh-row{display:grid;grid-template-columns:repeat(2,1fr);gap:5px;}
            .door-btn,.cat-btn,.sub-btn,.cf-side-btn,.tob-btn,.tsl-btn,.tsh-btn{padding:9px 3px;background:var(--input);
              border:1.5px solid var(--border-2);border-radius:5px;
              text-align:center;cursor:pointer;color:var(--text-2);font-family:inherit;
              font-size:11px;font-weight:600;}
            .door-btn:hover,.cat-btn:hover,.sub-btn:hover,.cf-side-btn:hover,.tob-btn:hover,.tsl-btn:hover,.tsh-btn:hover{border-color:#3a4453;color:var(--text);}
            .door-btn.active,.cat-btn.active,.sub-btn.active,.cf-side-btn.active,.tob-btn.active,.tsl-btn.active,.tsh-btn.active{border-color:var(--accent);
              background:linear-gradient(180deg,rgba(255,107,26,.14),rgba(255,107,26,.03));
              color:#fff;}

            .mat-actions{display:flex;flex-direction:column;gap:6px;margin-top:6px;}
            .mat-btn{padding:10px;background:#1a2029;border:1px solid var(--border-2);
              border-radius:5px;color:var(--text);cursor:pointer;font-family:inherit;
              font-size:11.5px;font-weight:600;}
            .mat-btn:hover{background:#202834;}
            .mat-btn.primary{background:linear-gradient(180deg,var(--accent-2),var(--accent));
              border-color:var(--accent);color:#fff;}
            .mat-btn.primary:hover{filter:brightness(1.08);}

            .footer{flex-shrink:0;display:flex;flex-direction:column;gap:6px;
              padding-top:8px;border-top:1px solid var(--border);}
            .apply-btn{width:100%;padding:11px;
              background:linear-gradient(180deg,var(--accent-2),var(--accent));
              color:#fff;border:0;border-radius:7px;font-family:inherit;
              font-size:13px;font-weight:700;cursor:pointer;
              box-shadow:0 3px 10px rgba(255,107,26,.28);}
            .apply-btn:hover{filter:brightness(1.08);}
            .apply-btn:disabled{opacity:.5;cursor:wait;}

            .row-actions{display:grid;grid-template-columns:1fr 1fr 1fr;gap:5px;}
            .mini-btn{padding:9px 4px;background:#1a2029;
              border:1px solid var(--border-2);border-radius:5px;color:var(--text);
              cursor:pointer;font-family:inherit;font-size:11px;font-weight:600;}
            .mini-btn:hover{background:#202834;}
            .mini-btn.danger{color:var(--danger);border-color:rgba(239,68,68,.35);}
            .status-line{font-size:11px;color:var(--text-3);text-align:center;min-height:14px;}
            .status-line.ok{color:#22c55e;}
            .status-line.err{color:var(--danger);}

            .drawer-heights{display:flex;flex-direction:column;gap:5px;margin-top:5px;}
            .dh-row{display:flex;align-items:center;gap:6px;}
            .dh-row label{font-size:11px;color:var(--text-2);min-width:50px;}
            .dh-row input{flex:1;background:var(--input);border:1px solid var(--border-2);
              border-radius:5px;height:30px;padding:0 8px;color:var(--text);
              font-size:12px;font-weight:600;text-align:center;outline:0;}
            .dh-row input:focus{border-color:var(--accent);}

            .hint-box{font-size:10.5px;color:#9aa3b1;line-height:1.6;
              padding:8px 10px;background:#0e1218;border:1px solid #232a35;
              border-radius:5px;margin-bottom:8px;}

            .num-row{display:flex;gap:6px;}
            .num-row .ctrl{flex:1;}
            .num-row .apply-num{width:auto;padding:0 14px;font-size:11px;
              font-weight:700;color:#fff;background:linear-gradient(180deg,var(--accent-2),var(--accent));
              border:0;border-radius:5px;cursor:pointer;font-family:inherit;}
            .num-row .apply-num:hover{filter:brightness(1.08);}
          </style>
          </head>
          <body>
            <div class="wrap">
              <div class="header">
                <div class="title">
                  <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M12 2 21 7v10l-9 5-9-5V7z"/>
                    <path d="M12 12 21 7M12 12 3 7M12 12v10"/>
                  </svg>
                  Cabinet Neo <span class="name" id="unitName">—</span>
                </div>
                <button class="close-x" id="closeBtn">✕</button>
              </div>

              <div class="main-area">
                <div class="side-preview">
                  <div class="unit-preview" id="unitPreview">
                    <img id="unitPreviewImg" src="" alt="preview"
                         onerror="this.style.display='none';"/>
                  </div>
                  <div class="type-badge" id="typeBadge">
                    <b id="typeBadgeLabel">—</b>
                    <span id="typeBadgeSub">—</span>
                  </div>
                </div>

                <div class="content-area">
                  <div class="tabs">
                    <button class="tab-btn active" data-tab="dims">📐 الأبعاد</button>
                    <button class="tab-btn" data-tab="door">🚪 الباب</button>
                    <button class="tab-btn" data-tab="mats">🎨 الخامات</button>
                  </div>

                  <div class="panes">
                    <div class="pane active" data-pane="dims">

                      <div class="section">
                        <div class="section-title">🔢 رقم الوحدة</div>
                        <div class="field">
                          <div class="field-label"><span>الرقم</span><span class="unit">الوصف ثابت</span></div>
                          <div class="num-row">
                            <div class="ctrl">
                              <input type="number" id="unitNum" min="1" max="9999" value="1"/>
                            </div>
                            <button class="apply-num" id="applyNumBtn">تطبيق</button>
                          </div>
                        </div>
                      </div>

                      <div class="section" id="dimsStandard">
                        <div class="section-title">📐 أبعاد الوحدة</div>
                        <div class="field">
                          <div class="field-label"><span>العرض</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="width" min="20" max="300" value="60"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>الارتفاع (الجسم)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="height" min="30" max="300" value="78"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>العمق</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="depth" min="20" max="150" value="58"/></div>
                        </div>
                        <div class="field" id="shelvesField">
                          <div class="field-label"><span>عدد الأرفف</span></div>
                          <div class="ctrl"><input type="number" id="shelves" min="0" max="8" value="1"/></div>
                        </div>
                      </div>

                      <div class="section" id="dimsDrawers" style="display:none;">
                        <div class="section-title">📐 أبعاد الوحدة</div>
                        <div class="field">
                          <div class="field-label"><span>العرض</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="widthD" min="20" max="300" value="60"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>الارتفاع (الجسم)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="heightD" min="30" max="300" value="78"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>العمق</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="depthD" min="20" max="150" value="58"/></div>
                        </div>
                      </div>

                      <div class="section" id="drawerHeightsSection" style="display:none;">
                        <div class="section-title">📏 ارتفاعات الأدراج (سم)</div>
                        <div class="hint-box">
                          💡 <strong style="color:#ff6b1a;">0</strong> = توزيع تلقائي<br>
                          📏 الحد الأدنى: 10 سم — الأقصى: 40 سم
                        </div>
                        <div class="drawer-heights" id="drawerHeightsList"></div>
                        <button class="mat-btn" id="addDrawerBtn" style="margin-top:8px;">➕ إضافة درج</button>
                        <button class="mat-btn" id="removeDrawerBtn" style="margin-top:4px;">➖ حذف آخر درج</button>
                      </div>

                      <div class="section" id="drawerBoxSection" style="display:none;">
                        <div class="section-title">📦 عمق صناديق الأدراج (سم)</div>
                        <div class="hint-box">💡 الحد الأدنى: 30 سم — الأقصى: 50 سم</div>
                        <div class="drawer-heights" id="drawerBoxDepthsList"></div>
                      </div>

                      <div class="section" id="dimsCorner" style="display:none;">
                        <div class="section-title">📐 أبعاد كورنر L</div>
                        <div class="field">
                          <div class="field-label"><span>الارتفاع (الجسم)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="heightC" min="30" max="300" value="78"/></div>
                        </div>
                        <div class="section-title accent">🔸 الضلع اليمين</div>
                        <div class="field">
                          <div class="field-label"><span>عرض اليمين</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cwRight" min="20" max="300" value="90"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>عمق اليمين</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cdRight" min="20" max="150" value="58"/></div>
                        </div>
                        <div class="section-title accent">🔸 الضلع الشمال</div>
                        <div class="field">
                          <div class="field-label"><span>عرض الشمال</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cwLeft" min="20" max="300" value="90"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>عمق الشمال</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cdLeft" min="20" max="150" value="58"/></div>
                        </div>
                      </div>

                      <div class="section" id="dimsCounterFixed" style="display:none;">
                        <div class="section-title">📐 أبعاد السدة</div>
                        <div class="field">
                          <div class="field-label"><span>العرض</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="widthCF" min="20" max="300" value="110"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>الارتفاع (الجسم)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="heightCF" min="30" max="300" value="78"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>العمق</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="depthCF" min="20" max="150" value="58"/></div>
                        </div>
                        <div class="section-title accent">⚙️ إعدادات السدة</div>
                        <div class="field">
                          <div class="field-label"><span>جهة الجزء الثابت</span></div>
                          <div class="cat-row" style="grid-template-columns:1fr 1fr;">
                            <button class="cf-side-btn" data-side="left">يسار</button>
                            <button class="cf-side-btn" data-side="right">يمين</button>
                          </div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>عرض السدة</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cfWidth" min="20" max="200" value="50"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>عرض القطعة الثابتة</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="cfFiller" min="5" max="50" value="15"/></div>
                        </div>
                      </div>
                    </div>

                    <div class="pane" data-pane="door">
                      <div class="section">
                        <div class="section-title">🚪 اتجاه الباب</div>
                        <div class="door-row">
                          <button class="door-btn" data-swing="left">يسار</button>
                          <button class="door-btn" data-swing="right">يمين</button>
                          <button class="door-btn" data-swing="double">بابان</button>
                        </div>
                      </div>
                      <div class="section">
                        <div class="section-title">🏷️ تصنيف الوحدة</div>
                        <div class="cat-row">
                          <button class="cat-btn" data-cat="lower">سفلي</button>
                          <button class="cat-btn" data-cat="upper">علوي</button>
                          <button class="cat-btn" data-cat="wardrobe">دولاب</button>
                          <button class="cat-btn" data-cat="balcony">بلكونة</button>
                        </div>
                      </div>
                      <div class="section">
                        <div class="section-title">🔧 النوع الفرعي</div>
                        <div class="sub-row">
                          <button class="sub-btn" data-sub="standard">عادي</button>
                          <button class="sub-btn" data-sub="drawers">أدراج</button>
                          <button class="sub-btn" data-sub="oven">فرن</button>
                          <button class="sub-btn" data-sub="sink">حوض</button>
                          <button class="sub-btn" data-sub="corner_L">كورنر L</button>
                          <button class="sub-btn" data-sub="counter_fixed">سدة كونتر</button>
                          <button class="sub-btn" data-sub="tall_oven">دولاب فرن</button>
                          <button class="sub-btn" data-sub="tall_storage">دولاب تخزين</button>
                        </div>
                      </div>
                      <div class="section" id="tallOvenBottomSection" style="display:none;">
                        <div class="section-title">🔽 القسم السفلي (تحت)</div>
                        <div class="tob-row">
                          <button class="tob-btn" data-tob="drawer1">درج واحد</button>
                          <button class="tob-btn active" data-tob="drawers">درجين</button>
                          <button class="tob-btn" data-tob="door">درفة</button>
                          <button class="tob-btn" data-tob="double">درفتين</button>
                        </div>
                        <div class="section-title" style="margin-top:12px;">📏 ارتفاعات الأقسام</div>
                        <div class="field">
                          <div class="field-label"><span>القسم السفلي (أدراج / درف)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tallBottomH" min="20" max="200" step="0.5" value="62"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>فتحة الفرن</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tallOvenH" min="20" max="200" step="0.5" value="60"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>درفة الميكروويف</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tallMicroH" min="10" max="200" step="0.5" value="45"/></div>
                        </div>
                        <div class="hint-box">الدرفة العلوية بتتحسب تلقائي من الباقي (الهواية 13 سم ثابتة)</div>
                      </div>

                      <div class="section" id="tallStorageSection" style="display:none;">
                        <div class="section-title">🗄️ شكل الأوجه (بدون فتحات)</div>
                        <div class="tsl-row">
                          <button class="tsl-btn active" data-tsl="door">درفة / درفتين</button>
                          <button class="tsl-btn" data-tsl="two_doors">درفتين فوق بعض</button>
                          <button class="tsl-btn" data-tsl="door_flip">درفة سفلية + قلاب</button>
                        </div>
                        <div class="field" style="margin-top:8px;">
                          <div class="field-label"><span>عدد الأدراج السفلية (0 - 4)</span></div>
                          <div class="ctrl"><input type="number" id="tsDrawerN" min="0" max="4" value="0"/></div>
                        </div>
                        <div class="field" id="tsDrawerHField" style="margin-top:8px;">
                          <div class="field-label"><span>ارتفاع كل درج</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tsDrawerH" min="10" max="60" step="0.5" value="25"/></div>
                        </div>
                        <div class="field" id="tsSplitHField" style="display:none;margin-top:8px;">
                          <div class="field-label"><span>ارتفاع الفاصل (من الأرض)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tsSplitH" min="40" max="300" step="1" value="120"/></div>
                        </div>
                        <div class="section-title" style="margin-top:12px;">🔘 المقابض</div>
                        <div class="tsh-row">
                          <button class="tsh-btn active" data-tsh="no">بدون مقابض (لمس)</button>
                          <button class="tsh-btn" data-tsh="yes">مقابض C و L</button>
                        </div>
                        <div class="section-title" style="margin-top:12px;">📚 الرفوف الداخلية (من الأرض)</div>
                        <div class="field">
                          <div class="field-label"><span>عدد الرفوف</span></div>
                          <div class="ctrl"><input type="number" id="tsShelves" min="0" max="12" value="4"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>فراغ سفلي بدون رفوف (مقاشات / نضافة)</span><span class="unit">سم</span></div>
                          <div class="ctrl"><input type="number" id="tsClearH" min="0" max="300" step="1" value="0"/></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>مواضع الرفوف يدوي (سم، بفاصلة)</span></div>
                          <div class="ctrl"><input type="text" id="tsShelfPos" placeholder="مثال: 150, 180, 200" value=""/></div>
                        </div>
                        <div class="hint-box">0 = توزيع عادي. أول رف بيبدأ عند نهاية الفراغ السفلي. لو كتبت مواضع يدوي بتتجاهل العدد والفراغ.</div>
                      </div>
                    </div>

                    <div class="pane" data-pane="mats">
                      <div class="section">
                        <div class="section-title">🎨 الخامات</div>
                        <div class="field">
                          <div class="field-label"><span>خامة الدرفة</span></div>
                          <div class="ctrl"><select id="doorMat"></select></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>حاشية الدرفة</span></div>
                          <div class="ctrl"><select id="doorEdge"></select></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>خامة العلب</span></div>
                          <div class="ctrl"><select id="carcassMat"></select></div>
                        </div>
                        <div class="field">
                          <div class="field-label"><span>حاشية العلب</span></div>
                          <div class="ctrl"><select id="carcassEdge"></select></div>
                        </div>
                      </div>
                      <div class="section">
                        <div class="section-title">⚡ تطبيق سريع</div>
                        <div class="mat-actions">
                          <button class="mat-btn primary" id="applyThisBtn">تطبيق على هذه الوحدة</button>
                          <button class="mat-btn" id="applyLowerBtn">تطبيق على كل السفلي</button>
                          <button class="mat-btn" id="applyUpperBtn">تطبيق على كل العلوي</button>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <div class="footer">
                <button class="apply-btn" id="applyBtn">تطبيق تغييرات المقاسات</button>
                <div class="row-actions">
                  <button class="mini-btn" id="openBtn">فتح</button>
                  <button class="mini-btn" id="closeDoorsBtn">إغلاق</button>
                  <button class="mini-btn danger" id="deleteBtn">حذف</button>
                </div>
                <div class="status-line" id="statusLine"></div>
              </div>
            </div>

            <script>
              (function(){
                var CB = {
                  ready:'cnp_ready', apply:'cnp_apply',
                  open:'cnp_open', closeDoors:'cnp_close_doors',
                  deleteUnit:'cnp_delete', closePopup:'cnp_close_popup',
                  loadMaterials:'cnp_load_materials',
                  applyMaterials:'cnp_apply_materials',
                  applyMaterialsToCat:'cnp_apply_materials_to_cat',
                  setCategory:'cnp_set_category',
                  setUnitNumber:'cnp_set_unit_number'
                };
                var pending = { door:'', doorEdge:'', carcass:'', carcassEdge:'' };
                var drawerHeights = [23, 23, 23];
                var drawerBoxDepths = [45, 45, 45];

                var SUBTYPE_LABELS = {
                  'standard':      { ar: 'وحدة عادية',  en: 'Standard' },
                  'drawers':       { ar: 'أدراج',       en: 'Drawers' },
                  'oven':          { ar: 'وحدة فرن',    en: 'Oven' },
                  'sink':          { ar: 'وحدة حوض',    en: 'Sink' },
                  'corner_L':      { ar: 'كورنر L',   en: 'Corner L' },
                  'counter_fixed': { ar: 'كورنر بسدة',   en: 'Counter Fixed' },
                  'tall_oven':     { ar: 'دولاب فرن',   en: 'Tall Oven' },
                  'tall_storage':  { ar: 'دولاب تخزين', en: 'Tall Storage' }
                };

                function setStatus(kind,msg){
                  var el=document.getElementById('statusLine');
                  if(!el)return; el.textContent=msg||'';
                  el.className='status-line'+(kind?' '+kind:'');
                }
                function flash(kind,msg){
                  setStatus(kind,msg);
                  setTimeout(function(){setStatus('','');},2500);
                }
                function callRuby(cbKey){
                  var args=Array.prototype.slice.call(arguments,1);
                  var name=CB[cbKey];
                  if(!window.sketchup){setStatus('err','Bridge not ready');return false;}
                  var fn=window.sketchup[name];
                  if(typeof fn!=='function'){setStatus('err','Missing: '+name);return false;}
                  try{fn.apply(null,args);return true;}catch(e){setStatus('err',e.message);return false;}
                }
                function setValue(id,val){var el=document.getElementById(id);if(el)el.value=val;}
                function getVal(id,def){var el=document.getElementById(id);return el?(parseFloat(el.value)||def):def;}

                function setSwing(s){
                  document.querySelectorAll('.door-btn').forEach(function(b){
                    b.classList.toggle('active',b.getAttribute('data-swing')===s);
                  });
                }
                function setCategory(c){
                  document.querySelectorAll('.cat-btn').forEach(function(b){
                    b.classList.toggle('active',b.getAttribute('data-cat')===c);
                  });
                }
                function setCfsSide(s){
                  document.querySelectorAll('.cf-side-btn').forEach(function(b){
                    b.classList.toggle('active', b.getAttribute('data-side') === s);
                  });
                }
                function setTallBottom(v){
                  document.querySelectorAll('.tob-btn').forEach(function(b){
                    b.classList.toggle('active', b.getAttribute('data-tob') === v);
                  });
                }
                function getTallBottom(){
                  var b = document.querySelector('.tob-btn.active');
                  return b ? b.getAttribute('data-tob') : 'drawers';
                }

                function setTsLayout(v){
                  document.querySelectorAll('.tsl-btn').forEach(function(b){
                    b.classList.toggle('active', b.getAttribute('data-tsl') === v);
                  });
                  updateTsRows();
                }
                function getTsLayout(){
                  var b = document.querySelector('.tsl-btn.active');
                  return b ? b.getAttribute('data-tsl') : 'door';
                }
                function setTsHandles(on){
                  document.querySelectorAll('.tsh-btn').forEach(function(b){
                    b.classList.toggle('active', (b.getAttribute('data-tsh') === 'yes') === !!on);
                  });
                }
                function getTsHandles(){
                  var b = document.querySelector('.tsh-btn.active');
                  return !!b && b.getAttribute('data-tsh') === 'yes';
                }
                function updateTsRows(){
                  var L = getTsLayout();
                  var b = document.getElementById('tsSplitHField');
                  if(b) b.style.display = (L === 'two_doors' || L === 'door_flip') ? 'block' : 'none';
                }
                function numOr(id, def){
                  var el = document.getElementById(id);
                  if(!el) return def;
                  var v = parseFloat(el.value);
                  return isNaN(v) ? def : v;
                }
                function readTsPayload(){
                  var pos = String((document.getElementById('tsShelfPos') || {}).value || '')
                    .split(/[,،\s]+/).map(function(x){ return parseFloat(x); })
                    .filter(function(x){ return !isNaN(x) && x > 0; })
                    .map(function(x){ return Math.round(x * 10); });
                  return {
                    layout:   getTsLayout(),
                    handles:  getTsHandles(),
                    drawer_n: Math.max(0, Math.min(4, Math.round(numOr('tsDrawerN', 0)))),
                    drawer_h: Math.round(numOr('tsDrawerH', 25) * 10),
                    split_h:  Math.round(numOr('tsSplitH', 120) * 10),
                    shelves:  Math.max(0, Math.min(12, Math.round(numOr('tsShelves', 4)))),
                    clear_h:  Math.round(numOr('tsClearH', 0) * 10),
                    shelf_pos: pos
                  };
                }
                function applyTallStorageLayout(s){
                  var sec = document.getElementById('tallStorageSection');
                  if(sec) sec.style.display = (s === 'tall_storage') ? 'block' : 'none';
                  updateTsRows();
                }

                function applyTallOvenLayout(s){
                  var sec = document.getElementById('tallOvenBottomSection');
                  if(sec) sec.style.display = (s === 'tall_oven') ? 'block' : 'none';
                }

                function applySubtypeLayout(s){
                  var ids = ['dimsStandard','dimsDrawers','dimsCorner','dimsCounterFixed',
                             'drawerHeightsSection','drawerBoxSection'];
                  ids.forEach(function(id){
                    var el = document.getElementById(id);
                    if(el) el.style.display = 'none';
                  });

                  if (s === 'drawers') {
                    document.getElementById('dimsDrawers').style.display = 'block';
                    document.getElementById('drawerHeightsSection').style.display = 'block';
                    document.getElementById('drawerBoxSection').style.display = 'block';
                  } else if (s === 'corner_L') {
                    document.getElementById('dimsCorner').style.display = 'block';
                  } else if (s === 'counter_fixed') {
                    document.getElementById('dimsCounterFixed').style.display = 'block';
                  } else if (s === 'tall_oven' || s === 'tall_storage') {
                    document.getElementById('dimsStandard').style.display = 'block';
                    var sf0 = document.getElementById('shelvesField');
                    if (sf0) sf0.style.display = 'none';
                  } else {
                    document.getElementById('dimsStandard').style.display = 'block';
                    var sf = document.getElementById('shelvesField');
                    if (sf) sf.style.display = (s === 'standard') ? 'flex' : 'none';
                  }

                  applyTallOvenLayout(s);
                  applyTallStorageLayout(s);
                }

                function setSubtype(s){
                  document.querySelectorAll('.sub-btn').forEach(function(b){
                    b.classList.toggle('active',b.getAttribute('data-sub')===s);
                  });
                  applySubtypeLayout(s);
                }

                function updateTypeBadge(subtype, cat){
                  var info = SUBTYPE_LABELS[subtype] || SUBTYPE_LABELS['standard'];
                  var catAr = { lower:'سفلي', upper:'علوي', wardrobe:'دولاب', balcony:'بلكونة' }[cat] || 'سفلي';
                  var lbl = document.getElementById('typeBadgeLabel');
                  var sb  = document.getElementById('typeBadgeSub');
                  if(lbl) lbl.textContent = info.ar;
                  if(sb)  sb.textContent  = catAr + ' · ' + info.en;
                }

                function getCategory(){
                  var b=document.querySelector('.cat-btn.active');
                  return b?b.getAttribute('data-cat'):'lower';
                }
                function getSubtype(){
                  var b=document.querySelector('.sub-btn.active');
                  return b?b.getAttribute('data-sub'):'standard';
                }
                function getSwing(){
                  var b=document.querySelector('.door-btn.active');
                  return b?b.getAttribute('data-swing'):'double';
                }

                function renderDrawerHeights(){
                  var list = document.getElementById('drawerHeightsList');
                  if (!list) return;
                  list.innerHTML = '';
                  drawerHeights.forEach(function(h, i){
                    var row = document.createElement('div');
                    row.className = 'dh-row';
                    row.innerHTML = '<label>درج ' + (i+1) + '</label>' +
                      '<input type="number" data-dh-index="' + i + '" value="' + h + '" min="0" max="40" step="0.5"/>' +
                      '<span style="color:var(--text-3);font-size:10px;">سم</span>';
                    list.appendChild(row);
                  });
                  list.querySelectorAll('input[data-dh-index]').forEach(function(inp){
                    inp.addEventListener('input', function(){
                      var idx = parseInt(inp.getAttribute('data-dh-index'), 10);
                      var v = parseFloat(inp.value);
                      if (!isNaN(v) && v >= 0 && v <= 40) drawerHeights[idx] = v;
                    });
                  });
                }
                function renderDrawerBoxDepths(){
                  var list = document.getElementById('drawerBoxDepthsList');
                  if (!list) return;
                  list.innerHTML = '';
                  drawerBoxDepths.forEach(function(d, i){
                    var row = document.createElement('div');
                    row.className = 'dh-row';
                    row.innerHTML = '<label>درج ' + (i+1) + '</label>' +
                      '<input type="number" data-dbd-index="' + i + '" value="' + d + '" min="30" max="50" step="0.5"/>' +
                      '<span style="color:var(--text-3);font-size:10px;">سم</span>';
                    list.appendChild(row);
                  });
                  list.querySelectorAll('input[data-dbd-index]').forEach(function(inp){
                    inp.addEventListener('input', function(){
                      var idx = parseInt(inp.getAttribute('data-dbd-index'), 10);
                      var v = parseFloat(inp.value);
                      if (!isNaN(v) && v >= 30 && v <= 50) drawerBoxDepths[idx] = v;
                    });
                  });
                }
                function populateSelect(id,arr,selected){
                  var el=document.getElementById(id);
                  if(!el)return;
                  var html='<option value="">— اختر —</option>';
                  (arr||[]).forEach(function(m){
                    var sel=(m.name===selected)?' selected':'';
                    html+='<option value="'+m.name+'"'+sel+'>'+m.name+'</option>';
                  });
                  el.innerHTML=html;
                }
                function getMaterialsPayload(){
                  return {
                    door_mat:    (document.getElementById('doorMat')||{}).value||'',
                    door_edge:   (document.getElementById('doorEdge')||{}).value||'',
                    carcass_mat: (document.getElementById('carcassMat')||{}).value||'',
                    carcass_edge:(document.getElementById('carcassEdge')||{}).value||''
                  };
                }

                document.querySelectorAll('.tab-btn').forEach(function(btn){
                  btn.addEventListener('click',function(){
                    var tab = btn.getAttribute('data-tab');
                    document.querySelectorAll('.tab-btn').forEach(function(b){
                      b.classList.toggle('active', b === btn);
                    });
                    document.querySelectorAll('.pane').forEach(function(p){
                      p.classList.toggle('active', p.getAttribute('data-pane') === tab);
                    });
                  });
                });

                window.CabinetNeoPopup = {
                  receive: function(data){
                    if(!data)return;

                    setValue('unitNum', data.unit_number || 1);

                    setValue('width',  data.width);
                    setValue('height', data.height);
                    setValue('depth',  data.depth);
                    setValue('shelves',data.shelf_count);

                    setValue('widthD', data.width);
                    setValue('heightD',data.height);
                    setValue('depthD', data.depth);

                    setValue('heightC', data.height);
                    if (data.corner_w_right) setValue('cwRight', (data.corner_w_right / 10).toFixed(1));
                    if (data.corner_w_left)  setValue('cwLeft',  (data.corner_w_left  / 10).toFixed(1));
                    if (data.corner_d_right) setValue('cdRight', (data.corner_d_right / 10).toFixed(1));
                    if (data.corner_d_left)  setValue('cdLeft',  (data.corner_d_left  / 10).toFixed(1));

                    setValue('widthCF', data.width);
                    setValue('heightCF',data.height);
                    setValue('depthCF', data.depth);
                    if (data.fixed_side)    setCfsSide(data.fixed_side);
                    if (data.counter_width) setValue('cfWidth',  (data.counter_width / 10).toFixed(1));
                    if (data.filler_width)  setValue('cfFiller', (data.filler_width  / 10).toFixed(1));

                    setSwing(data.door_swing||'double');
                    setCategory(data.unit_category||'lower');

                    var subtype = data.unit_subtype || 'standard';
                    setSubtype(subtype);
                    updateTypeBadge(subtype, data.unit_category||'lower');

                    setTallBottom(data.tall_bottom_type || 'drawers');
                    setValue('tallBottomH', ((data.tall_bottom_h || 620) / 10).toFixed(1));
                    setValue('tallOvenH',   ((data.tall_oven_h   || 600) / 10).toFixed(1));
                    setValue('tallMicroH',  ((data.tall_micro_h  || 450) / 10).toFixed(1));

                    var tsd = data.ts || {};
                    setTsLayout(tsd.layout || 'door');
                    setTsHandles(!!tsd.handles);
                    setValue('tsDrawerN', tsd.drawer_n || 0);
                    setValue('tsDrawerH', ((tsd.drawer_h || 250) / 10).toFixed(1));
                    setValue('tsSplitH',  Math.round((tsd.split_h || 1200) / 10));
                    setValue('tsShelves', (tsd.shelves === undefined || tsd.shelves === null) ? 4 : tsd.shelves);
                    setValue('tsClearH',  Math.round((tsd.clear_h || 0) / 10));
                    setValue('tsShelfPos', (tsd.shelf_pos || []).map(function(v){ return Math.round(v / 10); }).join(', '));

                    var n=document.getElementById('unitName');
                    if(n)n.textContent=data.name||'';

                    pending.door        = data.mat_door         || '';
                    pending.doorEdge    = data.mat_door_edge    || '';
                    pending.carcass     = data.mat_carcass      || '';
                    pending.carcassEdge = data.mat_carcass_edge || '';

                    if (data.drawer_heights && data.drawer_heights.length > 0) {
                      drawerHeights = data.drawer_heights.map(function(v){
                        var cm = v / 10;
                        return Math.round(cm * 10) / 10;
                      });
                    } else {
                      drawerHeights = [23, 23, 23];
                    }
                    if (data.drawer_box_depths && data.drawer_box_depths.length > 0) {
                      drawerBoxDepths = data.drawer_box_depths.map(function(v){
                        return Math.round(v * 10) / 10;
                      });
                    } else {
                      drawerBoxDepths = drawerHeights.map(function(){ return 45; });
                    }

                    var subtypeMap = {
                      'standard':'standard','drawers':'drawers','oven':'oven',
                      'sink':'sink','corner_L':'corner_L','counter_fixed':'counter_fixed',
                      'tall_oven':'tall_oven','tall_storage':'tall_storage'
                    };
                    var imgName = subtypeMap[subtype] || 'standard';
                    var previewImg = document.getElementById('unitPreviewImg');
                    if (previewImg && data.preview_base) {
                      previewImg.style.display = '';
                      previewImg.src = data.preview_base + imgName + '.png';
                    }

                    renderDrawerHeights();
                    renderDrawerBoxDepths();
                  },
                  receiveMaterials: function(data){
                    if(!data)return;
                    populateSelect('doorMat',    data.boards||[], pending.door);
                    populateSelect('doorEdge',   data.edges ||[], pending.doorEdge);
                    populateSelect('carcassMat', data.boards||[], pending.carcass);
                    populateSelect('carcassEdge',data.edges ||[], pending.carcassEdge);
                  },
                  flashStatus: function(kind,msg){ flash(kind,msg); }
                };

                document.addEventListener('keydown',function(e){
                  var tag=(e.target&&e.target.tagName)?e.target.tagName:'';
                  if(tag==='INPUT'||tag==='TEXTAREA'||tag==='SELECT')return;
                  if(e.key==='Delete'||e.key==='Backspace'){
                    e.preventDefault();
                    if(confirm('حذف الوحدة؟')) callRuby('deleteUnit');
                  } else if(e.key==='Escape'){
                    e.preventDefault(); callRuby('closePopup');
                  }
                });

                document.querySelectorAll('.door-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    document.querySelectorAll('.door-btn').forEach(function(x){x.classList.remove('active');});
                    b.classList.add('active');
                  });
                });
                document.querySelectorAll('.cat-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    document.querySelectorAll('.cat-btn').forEach(function(x){x.classList.remove('active');});
                    b.classList.add('active');
                    callRuby('setCategory',b.getAttribute('data-cat'));
                    updateTypeBadge(getSubtype(), b.getAttribute('data-cat'));
                  });
                });
                document.querySelectorAll('.sub-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    var prevSub = getSubtype();
                    document.querySelectorAll('.sub-btn').forEach(function(x){x.classList.remove('active');});
                    b.classList.add('active');
                    var s = b.getAttribute('data-sub');
                    // الارتفاع الافتراضي 78 لكل الوحدات، ودولاب الفرن 220 (بدون الرجل)
                    if (s === 'tall_oven' || s === 'tall_storage') {
                      if (getVal('height', 78) < 150) setValue('height', 220);
                    } else if ((prevSub === 'tall_oven' || prevSub === 'tall_storage') && getVal('height', 78) >= 150) {
                      setValue('height', 78);
                    }
                    setSubtype(s);
                    updateTypeBadge(s, getCategory());
                  });
                });
                document.querySelectorAll('.tsl-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    var v = b.getAttribute('data-tsl');
                    setTsLayout(v);
                    if (v === 'door_flip') setValue('tsSplitH', 170);
                    else if (v === 'two_doors') setValue('tsSplitH', 120);
                  });
                });
                document.querySelectorAll('.tsh-btn').forEach(function(b){
                  b.addEventListener('click',function(){ setTsHandles(b.getAttribute('data-tsh') === 'yes'); });
                });
                document.querySelectorAll('.cf-side-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    document.querySelectorAll('.cf-side-btn').forEach(function(x){x.classList.remove('active');});
                    b.classList.add('active');
                  });
                });
                document.querySelectorAll('.tob-btn').forEach(function(b){
                  b.addEventListener('click',function(){
                    document.querySelectorAll('.tob-btn').forEach(function(x){x.classList.remove('active');});
                    b.classList.add('active');
                  });
                });

                document.getElementById('addDrawerBtn').addEventListener('click', function(){
                  if (drawerHeights.length < 6) {
                    drawerHeights.push(0);
                    drawerBoxDepths.push(45);
                    renderDrawerHeights();
                    renderDrawerBoxDepths();
                  }
                });
                document.getElementById('removeDrawerBtn').addEventListener('click', function(){
                  if (drawerHeights.length > 1) {
                    drawerHeights.pop();
                    drawerBoxDepths.pop();
                    renderDrawerHeights();
                    renderDrawerBoxDepths();
                  }
                });

                document.getElementById('applyNumBtn').addEventListener('click', function(){
                  var n = parseInt(document.getElementById('unitNum').value, 10);
                  if (!n || n < 1) { flash('err', 'رقم غير صحيح'); return; }
                  callRuby('setUnitNumber', String(n));
                });

                document.getElementById('applyBtn').addEventListener('click',function(){
                  var subtype = getSubtype();
                  var w=60, h=78, d=58, shelves=0;
                  var cwr=90, cwl=90, cdr=58, cdl=58;
                  var cfSide='left', cfW=50, cfF=15;

                  if (subtype === 'corner_L') {
                    h   = getVal('heightC', 78);
                    cwr = getVal('cwRight', 90);
                    cdr = getVal('cdRight', 58);
                    cwl = getVal('cwLeft',  90);
                    cdl = getVal('cdLeft',  58);
                  } else if (subtype === 'counter_fixed') {
                    w = getVal('widthCF', 110);
                    h = getVal('heightCF',78);
                    d = getVal('depthCF', 58);
                    var sb = document.querySelector('.cf-side-btn.active');
                    cfSide = sb ? sb.getAttribute('data-side') : 'left';
                    cfW = getVal('cfWidth',  50);
                    cfF = getVal('cfFiller', 15);
                  } else if (subtype === 'drawers') {
                    w = getVal('widthD', 60);
                    h = getVal('heightD',78);
                    d = getVal('depthD', 58);
                  } else if (subtype === 'tall_oven' || subtype === 'tall_storage') {
                    w = getVal('width', 60);
                    h = getVal('height',78);
                    d = getVal('depth', 58);
                  } else {
                    w = getVal('width', 60);
                    h = getVal('height',78);
                    d = getVal('depth', 58);
                    var shel = document.getElementById('shelves');
                    shelves = shel ? (parseInt(shel.value,10)||0) : 0;
                  }

                  var p = {
                    width: w, height: h, depth: d, shelves: shelves,
                    door_swing: getSwing(),
                    unit_category: getCategory(),
                    unit_subtype: subtype,
                    drawer_heights: drawerHeights.map(function(v){ return Math.round(v * 10); }),
                    drawer_box_depths: drawerBoxDepths.map(function(v){ return Math.round(v * 10); }),
                    corner_w_right: cwr * 10,
                    corner_w_left:  cwl * 10,
                    corner_d_right: cdr * 10,
                    corner_d_left:  cdl * 10,
                    fixed_side:     cfSide,
                    counter_width:  cfW * 10,
                    filler_width:   cfF * 10,
                    tall_bottom_type: getTallBottom(),
                    tall_bottom_h: Math.round(getVal('tallBottomH', 62) * 10),
                    tall_oven_h:   Math.round(getVal('tallOvenH',   60) * 10),
                    tall_micro_h:  Math.round(getVal('tallMicroH',  45) * 10),
                    ts: readTsPayload()
                  };
                  var btn=this; btn.disabled=true;
                  setStatus('','جاري التطبيق...');
                  var ok=callRuby('apply',JSON.stringify(p));
                  if(ok){setStatus('ok','تم الإرسال');
                    setTimeout(function(){setStatus('','');btn.disabled=false;},1500);}
                  else{btn.disabled=false;}
                });

                document.getElementById('applyThisBtn').addEventListener('click',function(){
                  var p=getMaterialsPayload();
                  if(!p.door_mat&&!p.carcass_mat){flash('err','اختر خامة');return;}
                  callRuby('applyMaterials',JSON.stringify(p));
                });
                document.getElementById('applyLowerBtn').addEventListener('click',function(){
                  var p=getMaterialsPayload(); p.category='lower';
                  if(!p.door_mat&&!p.carcass_mat){flash('err','اختر خامة');return;}
                  callRuby('applyMaterialsToCat',JSON.stringify(p));
                });
                document.getElementById('applyUpperBtn').addEventListener('click',function(){
                  var p=getMaterialsPayload(); p.category='upper';
                  if(!p.door_mat&&!p.carcass_mat){flash('err','اختر خامة');return;}
                  callRuby('applyMaterialsToCat',JSON.stringify(p));
                });

                document.getElementById('openBtn').addEventListener('click',function(){callRuby('open');});
                document.getElementById('closeDoorsBtn').addEventListener('click',function(){callRuby('closeDoors');});
                document.getElementById('deleteBtn').addEventListener('click',function(){
                  if(confirm('حذف الوحدة؟'))callRuby('deleteUnit');
                });
                document.getElementById('closeBtn').addEventListener('click',function(){callRuby('closePopup');});

                renderDrawerHeights();
                renderDrawerBoxDepths();
                applySubtypeLayout('standard');

                function announceReady(attempt){
                  attempt=attempt||1;
                  if(window.sketchup&&typeof window.sketchup[CB.ready]==='function'){callRuby('ready');return;}
                  if(attempt<30){setTimeout(function(){announceReady(attempt+1);},100);}
                }
                if(document.readyState==='loading'){
                  document.addEventListener('DOMContentLoaded',function(){announceReady(1);});
                }else{announceReady(1);}
              })();
            </script>
          </body>
          </html>
        HTML
      end
    end

    class SelectionObserver < Sketchup::SelectionObserver
      def initialize; super; end

      def onSelectionBulkChange(selection)
        return if SelectionPopup.instance.send(:suppress_next?)
        popup = SelectionPopup.instance
        return unless popup.visible?
        return unless selection.size == 1
        entity = selection[0]
        return unless entity.is_a?(Sketchup::ComponentInstance)
        return unless entity.definition.get_attribute('CabinetNeo', 'generated', false)
        return unless entity.definition.name.to_s =~ /^وحدة/
        popup.show(entity)
      end

      def onSelectionCleared(_s); end
    end
  end
end

CabinetNeo.cleanup_popup if defined?(CabinetNeo) && CabinetNeo.respond_to?(:cleanup_popup)