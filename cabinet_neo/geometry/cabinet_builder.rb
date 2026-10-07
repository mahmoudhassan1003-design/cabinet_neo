# encoding: UTF-8
# =============================================================================
# باني الخزانة — v79.19 (tall_oven + auto-attach + naming + skip_zoom default)
# v79.18: دولاب الفرن 220 (بدون الرجل) + تحكم في ارتفاع القسم السفلي/الفرن/درفة الميكروويف
#         + قسم سفلي: درج / درجين / درفة / درفتين + مقابض الأدراج ثابتة
#         + درف الكورنر مفصلية بتفتح 170° (باقي الوحدات 90°) + مقابض الكورنر L + وزر دولاب الفرن
# v79.19: إصلاح حواشي الجوانب (build_side_with_notches) + حواشي صناديق الأدراج
#         + السقفية تستخدم :top بدل :floor
# =============================================================================

module CabinetNeo
  module Geometry
    module CabinetBuilder
      C = Constants

      UNIT_TAG_NAMES = {
        'lower'    => 'سفلي',
        'upper'    => 'علوي',
        'wardrobe' => 'دولاب',
        'balcony'  => 'بلكونة'
      }.freeze

      UNIT_TAG_COLORS = {
        'lower'    => [255, 107, 26],
        'upper'    => [46, 204, 113],
        'wardrobe' => [52, 152, 219],
        'balcony'  => [155, 89, 182]
      }.freeze

      BUILD_DRAWER_FRONTS = true
      OVEN_DRAWER_FRONT_H = 150.0
      BOX_H_MIN_HARD      = 80.0
      DRAWER_OPEN_MM      = 400.0
      TALL_DEFAULT_HEIGHT_MM = 2200.0
      DOOR_OPEN_ANGLE        = 90.0
      CORNER_DOOR_OPEN_ANGLE = 170.0

      def self.tag_drawer_part(ent, d)
        return unless ent && ent.respond_to?(:valid?) && ent.valid?
        open_mm = [DRAWER_OPEN_MM, d.to_mm - 150.0].min
        open_mm = 100.0 if open_mm < 100.0
        ent.set_attribute('CabinetNeo', 'drawer_slide', true)
        ent.set_attribute('CabinetNeo', 'drawer_open_mm', open_mm)
        ent.set_attribute('CabinetNeo', 'drawer_offset_mm', 0.0)
      end

      def self.unit_descriptor(unit_subtype, door_type = 'double')
        case unit_subtype.to_s
        when 'standard'
          door_type.to_s == 'double' ? 'درفتین' : 'درفة'
        when 'drawers'       then 'أدراج'
        when 'oven'          then 'فرن'
        when 'sink'          then 'حوض'
        when 'corner_L'      then 'كورنر L'
        when 'counter_fixed' then 'سدة كونتر'
        when 'tall_oven'     then 'دولاب فرن'
        when 'tall_storage'  then 'دولاب تخزين'
        else                      'وحدة'
        end
      end

      def self.unit_full_name(num, unit_subtype, door_type = 'double')
        "وحدة #{num} - #{unit_descriptor(unit_subtype, door_type)}"
      end

      def self.rename_unit_number(instance, old_num, new_num)
        return unless instance && instance.valid?
        old_p = "وحدة #{old_num}"
        new_p = "وحدة #{new_num}"
        defn  = instance.definition

        if instance.name.to_s.include?(old_p)
          instance.name = instance.name.sub(old_p, new_p)
        end

        if defn.name.to_s.include?(old_p)
          defn.name = defn.name.sub(old_p, new_p)
        end

        display = defn.get_attribute('CabinetNeo', 'display_name')
        if display.to_s.include?(old_p)
          defn.set_attribute('CabinetNeo', 'display_name', display.to_s.sub(old_p, new_p))
        end

        defn.set_attribute('CabinetNeo', 'unit_number', new_num)
        rename_children(defn.entities, old_p, new_p)

        puts "[Cabinet Neo] 🔢 renamed وحدة #{old_num} → وحدة #{new_num}"
      rescue StandardError => e
        puts "[Cabinet Neo] rename_unit_number: #{e.message}"
      end

      def self.rename_children(entities, old_p, new_p)
        entities.each do |e|
          next unless e.respond_to?(:name)
          if e.name.to_s.include?(old_p)
            e.name = e.name.sub(old_p, new_p)
          end
          if e.is_a?(Sketchup::ComponentInstance)
            rename_children(e.definition.entities, old_p, new_p)
          elsif e.is_a?(Sketchup::Group)
            rename_children(e.entities, old_p, new_p)
          end
        end
      rescue StandardError
      end

      def self.find_last_unit(model)
        best = nil
        best_num = 0
        model.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance)
          next unless ent.definition.get_attribute('CabinetNeo', 'generated', false)
          num = ent.definition.get_attribute('CabinetNeo', 'unit_number', 0).to_i
          if num > best_num
            best_num = num
            best = ent
          end
        end
        best
      end

      def self.set_dc(defn, key, value, access: nil, label: nil, options: nil)
        defn.set_attribute('dynamic_attributes', "#{key}_formula", '')
        defn.set_attribute('dynamic_attributes', key, value.to_s)
        defn.set_attribute('dynamic_attributes', "#{key}_access",  access)  if access
        defn.set_attribute('dynamic_attributes', "#{key}_label",   label)   if label
        defn.set_attribute('dynamic_attributes', "#{key}_options", options) if options
      end

      def self.parse_len(str, default = 0.0)
        return default if str.nil?
        s = str.to_s.strip
        return default if s.empty?
        s.sub(/[^\d\.\-]/, '').to_f
      end

      def self.activate_dc(defn)
        defn.set_attribute('dynamic_attributes', '_hasbehaviors', '1')
        defn.set_attribute('dynamic_attributes', '_islengths',    '1')
        defn.set_attribute('dynamic_attributes', 'name',          defn.name)
      end

      def self.wakeup_dc(instance)
        return unless instance.is_a?(Sketchup::ComponentInstance)
        defn = instance.definition
        defn.set_attribute('dynamic_attributes', '_rebuild_token', Time.now.to_i.to_s)
        name = defn.name
        defn.name = "#{name}_dc_tmp"
        defn.name = name
      end

      def self.force_delete_unit_definitions(model, unit_name)
        deleted = 0
        base = unit_name.gsub(/_dc.*$/, '').gsub(/_\d+$/, '')
        model.definitions.to_a.each do |d|
          n = d.name.to_s
          is_match = (n == base) ||
                     n.start_with?("#{base}#") ||
                     n.start_with?("#{base} #") ||
                     n.start_with?("#{base}_dc")
          next unless is_match
          next unless d.instances.empty?
          begin
            d.erase! if d.valid?
            deleted += 1
          rescue StandardError
          end
        end
        puts "[Cabinet Neo] 🧹 حذف #{deleted} تعريف سابق" if deleted > 0
      end

      def self.cleanup_orphan_definitions(model)
        return unless model
        removed = 0
        model.definitions.to_a.each do |d|
          next unless d.get_attribute('CabinetNeo', 'generated', false)
          next unless d.instances.empty?
          begin
            d.erase!
            removed += 1
          rescue StandardError
          end
        end
        puts "[Cabinet Neo] 🧹 حذف #{removed} تعريف يتيم" if removed > 0
      end

      def self.resolve_edge_config(piece_key, custom_config = nil)
        if custom_config && custom_config[piece_key.to_s]
          raw = custom_config[piece_key.to_s]
          return raw.each_with_object({}) do |(k, v), h|
            h[k.to_sym] = v.to_s.to_sym if v
          end
        end
        C::EDGE_FACES_DEFAULT[piece_key.to_sym] || {}
      end

      def self.assign_unit_tag(instance, cabinet_type)
        return unless instance.is_a?(Sketchup::ComponentInstance)
        model = Sketchup.active_model
        tag_name = UNIT_TAG_NAMES[cabinet_type.to_s] || UNIT_TAG_NAMES['lower']
        layer = model.layers[tag_name] || model.layers.add(tag_name)
        if layer.respond_to?(:color=)
          rgb = UNIT_TAG_COLORS[cabinet_type.to_s] || UNIT_TAG_COLORS['lower']
          begin
            layer.color = Sketchup::Color.new(*rgb)
          rescue StandardError
          end
        end
        instance.layer = layer
        puts "[Cabinet Neo] 🏷️  Tagged as '#{tag_name}'"
      rescue StandardError => e
        puts "[Cabinet Neo] assign_unit_tag failed: #{e.message}"
      end

      def self.apply_face_materials_by_normal(entity, mat_map)
        return unless entity && entity.valid?
        ents = if entity.is_a?(Sketchup::ComponentInstance)
                 entity.definition.entities
               elsif entity.is_a?(Sketchup::Group)
                 entity.entities
               end
        return unless ents
        model = Sketchup.active_model
        ents.grep(Sketchup::Face).each do |f|
          n = f.normal
          dir = if n.z.abs > 0.9
                  n.z > 0 ? :top : :bottom
                elsif n.y.abs > 0.9
                  n.y > 0 ? :front_y : :back_y
                elsif n.x.abs > 0.9
                  n.x > 0 ? :front_x : :back_x
                end
          next unless dir
          mat_name = mat_map[dir]
          next unless mat_name
          mat = model.materials[mat_name.to_s]
          next unless mat
          f.material      = mat
          f.back_material = mat
        end
      rescue StandardError => e
        puts "[Cabinet Neo] apply_face_materials_by_normal: #{e.message}"
      end

      def self.build_L_horizontal_panel(ents, ox, oy, w1, d1, w2, d2,
                                         t, z_bottom, name, material,
                                         edge_config = nil, mats = nil)
        grp = ents.add_group
        grp.name = name
        grp.set_attribute('CabinetNeo', 'generated', true)
        grp.set_attribute('CabinetNeo', 'piece_name', name)
        ge = grp.entities
        z_top = z_bottom + t

        pts = [
          Geom::Point3d.new(ox,        oy,        z_top),
          Geom::Point3d.new(ox + w1,   oy,        z_top),
          Geom::Point3d.new(ox + w1,   oy + d1,   z_top),
          Geom::Point3d.new(ox + d2,   oy + d1,   z_top),
          Geom::Point3d.new(ox + d2,   oy + w2,   z_top),
          Geom::Point3d.new(ox,        oy + w2,   z_top)
        ]

        face = ge.add_face(pts)
        if face
          face.reverse! if face.normal.z < 0
          face.pushpull(-t)

          ge.grep(Sketchup::Face).each do |f|
            if material
              f.material      = material
              f.back_material = material
            end
          end

          if edge_config && !edge_config.empty?
            model = Sketchup.active_model
            front_name = edge_config[:front] || edge_config['front']
            back_name  = edge_config[:back]  || edge_config['back']
            front_mat = (front_name && !front_name.to_s.empty?) ? model.materials[front_name.to_s] : nil
            back_mat  = (back_name  && !back_name.to_s.empty?)  ? model.materials[back_name.to_s]  : nil
            ge.grep(Sketchup::Face).each do |f|
              n = f.normal
              next if n.z.abs > 0.9
              if (n.y > 0.9 || n.x > 0.9) && front_mat
                f.material      = front_mat
                f.back_material = front_mat
              elsif (n.y < -0.9 || n.x < -0.9) && back_mat
                f.material      = back_mat
                f.back_material = back_mat
              end
            end
          end
        end
        grp
      rescue StandardError => e
        puts "[Cabinet Neo] build_L_horizontal_panel: #{e.message}"
        puts e.backtrace.first(4).join("\n")
        nil
      end

      def self.ensure_ocl_common(ocl)
        ocl['std_prices']             ||= '[{"val":"","dim":null}]'
        ocl['std_cut_prices']         ||= '[{"val":"","dim":null}]'
        ocl['std_volumic_masses']     ||= '[{"val":"","dim":null}]'
        ocl['multiplier_coefficient'] ||= 1.0
        ocl['raw_estimated']          ||= true
        ocl['description']            ||= ''
        ocl['url']                    ||= ''
      end

      def self.get_handle_L_material(model, fallback)
        mat = model.materials['مقبض L']
        unless mat
          mat = model.materials.add('مقبض L')
          mat.color = Sketchup::Color.new(10, 10, 10)
        end
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 3
        ocl['uuid'] ||= SecureRandom.uuid
        ocl['std_sections'] = "55 mm x 20 mm"
        ocl['std_lengths']  = "4000 mm;6000 mm"
        ocl['description']  = 'مقبض حرف L'
        ensure_ocl_common(ocl)
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] get_handle_L_material: #{e.message}"
        fallback
      end

      def self.get_handle_C_material(model, fallback)
        mat = model.materials['مقبض C']
        unless mat
          mat = model.materials.add('مقبض C')
          mat.color = Sketchup::Color.new(10, 10, 10)
        end
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 3
        ocl['uuid'] ||= SecureRandom.uuid
        ocl['std_sections'] = "55 mm x 20 mm"
        ocl['std_lengths']  = "4000 mm;6000 mm"
        ocl['description']  = 'مقبض حرف C'
        ensure_ocl_common(ocl)
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] get_handle_C_material: #{e.message}"
        fallback
      end

      def self.get_plinth_material(model, fallback)
        mat = model.materials['قضيب خشبي وزر']
        unless mat
          mat = model.materials.add('قضيب خشبي وزر')
          mat.color = Sketchup::Color.new(10, 10, 10)
        end
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 3
        ocl['uuid'] ||= SecureRandom.uuid
        ocl['std_sections'] = "100 mm x 10 mm"
        ocl['std_lengths']  = "4000 mm;6000 mm"
        ocl['description']  = 'وزر قضيب خشبي'
        ensure_ocl_common(ocl)
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] get_plinth_material: #{e.message}"
        fallback
      end

      def self.get_hardware_material(model, fallback)
        mat = model.materials['عتاد'] ||
              model.materials['اكسسوار'] ||
              model.materials['مقبض حرف L اسود']
        unless mat
          mat = model.materials.to_a.find do |m|
            ocl = m.attribute_dictionary('ladb_opencutlist', false)
            next false unless ocl
            ocl['type'].to_i == 5
          end
        end
        return fallback unless mat
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 5
        ocl['uuid'] ||= SecureRandom.uuid
        ensure_ocl_common(ocl)
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] get_hardware_material: #{e.message}"
        fallback
      end

      def self.get_sink_material(model)
        mat = model.materials['بورديوم']
        unless mat
          mat = model.materials.add('بورديوم')
          mat.color = Sketchup::Color.new(210, 180, 140)
        end
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 2
        ocl['uuid'] ||= SecureRandom.uuid
        ocl['std_thicknesses'] = "17 mm"
        ocl['std_sizes']       = "2800 mm x 2070 mm;2440 mm x 1220 mm"
        ensure_ocl_common(ocl)
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] get_sink_material: #{e.message}"
        nil
      end

      def self.ensure_back_panel_ocl(model)
        mat = model.materials['ظهور بورديوم 6مملي'] ||
              model.materials.to_a.find { |m| m.name.to_s.include?('بورديوم') && m.name.to_s.include?('6') }
        return unless mat
        ocl = mat.attribute_dictionary('ladb_opencutlist', true)
        ocl['type'] = 2
        ocl['uuid'] ||= SecureRandom.uuid
        ocl['std_thicknesses'] = "6 mm;15 mm;18 mm;22 mm"
        ocl['std_sizes']       = "2800 mm x 2070 mm;2440 mm x 1220 mm"
        ensure_ocl_common(ocl)
        puts "[Cabinet Neo] 🎨 ضبط OCL للضهر '#{mat.name}'"
      rescue StandardError => e
        puts "[Cabinet Neo] ensure_back_panel_ocl: #{e.message}"
      end

      def self.ensure_sink_mat_ocl(model)
        counter = model.materials['كونتر']
        if counter
          ocl = counter.attribute_dictionary('ladb_opencutlist', true)
          ocl['type'] ||= 2
          ocl['uuid'] ||= SecureRandom.uuid
          current = ocl['std_sizes'].to_s
          new_size = "2440 mm x 1220 mm"
          unless current.include?('2440')
            ocl['std_sizes'] = current.empty? ? new_size : "#{current};#{new_size}"
          end
          ensure_ocl_common(ocl)
        end
        edge = model.materials['شريط ابيض مط1']
        if edge
          ocl = edge.attribute_dictionary('ladb_opencutlist', true)
          ocl['type'] = 4
          ocl['uuid'] ||= SecureRandom.uuid
          ocl['std_widths']      = "18 mm"
          ocl['std_thicknesses'] = "1 mm"
          ocl['std_lengths']     = "2400 mm;6000 mm;13000 mm"
          ensure_ocl_common(ocl)
        end
      rescue StandardError => e
        puts "[Cabinet Neo] ensure_sink_mat_ocl: #{e.message}"
      end

      def self.compute_drawer_layout(h, drawer_heights)
        z0  = C::PLINTH_HEIGHT.mm
        z_t = z0 + h
        gap = C::DRAWER_GAP.mm
        gt  = C::DOOR_GAP_TOP.mm

        n = drawer_heights.size
        n = C::DRAWER_HEIGHTS_DEFAULT.size if n == 0
        n = 1 if n < 1

        available_h = h - gt - (n - 1) * gap
        return [] if available_h <= 0

        raw = drawer_heights.map { |x| x.to_f > 0 ? x.to_f.mm : 0.0 }
        fixed_sum  = raw.select { |x| x > 0 }.sum
        auto_count = raw.count { |x| x <= 0 }

        if fixed_sum > available_h
          scale = available_h / fixed_sum
          raw = raw.map { |x| x > 0 ? x * scale : 0.0 }
          fixed_sum  = raw.select { |x| x > 0 }.sum
          auto_count = raw.count { |x| x <= 0 }
        end

        if auto_count > 0
          remaining = available_h - fixed_sum
          if remaining <= 0
            unit_h = 10.0.mm
            heights = raw.map { |x| x > 0 ? x : unit_h }
          else
            unit_h = remaining / auto_count
            heights = raw.map { |x| x > 0 ? x : unit_h }
          end
        else
          diff = available_h - fixed_sum
          heights = raw.dup
          if diff.abs > 0.1.mm && !heights.empty?
            add_each = diff / heights.size.to_f
            heights = heights.map { |hh| hh + add_each }
          end
        end

        min_h = 10.0.mm
        heights = heights.map { |x| x > min_h ? x : min_h }

        current_top = z_t - gt
        drawer_data = []
        heights.each_with_index do |dh, i|
          current_bottom = current_top - dh
          drawer_data << {
            index:  i,
            bottom: current_bottom,
            top:    current_top,
            dh:     dh,
            is_top: (i == 0)
          }
          current_top = current_bottom - gap
        end
        drawer_data
      end

      def self.compute_side_notches(drawer_data)
        return nil if drawer_data.nil? || drawer_data.empty?
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm
        drop = 25.0.mm
        notches = drawer_data.map do |dd|
          z_bot = dd[:top] - drop
          z_top = z_bot + nh_h
          [z_bot.to_f, z_top.to_f]
        end
        notches.sort_by { |n| n[0] }
      end

      def self.build_side_profile_pts(z0, z_t, d, t, nh_d, nh_h, notches)
        pts = []
        pts << [0.0, (z0 + t).to_f]
        pts << [d.to_f, (z0 + t).to_f]

        if notches.nil? || notches.empty?
          notches_use = [[(z_t - nh_h).to_f, z_t.to_f]]
        else
          notches_use = notches
        end

        notches_use.each do |(bot_z, top_z)|
          bz = [[bot_z.to_f, (z0 + t).to_f].max, z_t.to_f].min
          tz = [[top_z.to_f, bz].max, z_t.to_f].min
          next if bz >= tz
          pts << [d.to_f, bz]
          pts << [(d - nh_d).to_f, bz]
          pts << [(d - nh_d).to_f, tz]
          pts << [d.to_f, tz] if tz < z_t.to_f - 0.5
        end

        unless pts.last[1] > z_t.to_f - 0.5
          pts << [d.to_f, z_t.to_f]
        end
        pts << [0.0, z_t.to_f]
        pts
      end

      def self.build(params)
        model = Sketchup.active_model
        raise 'No active model.' unless model

        skip_zoom     = params[:skip_zoom] != false
        skip_purge    = params[:skip_purge] == true
        own_operation = params[:own_operation] != false
        custom_name   = params[:custom_name]
        custom_edges  = params[:edge_faces]

        if params[:unit_subtype].to_s == 'corner'
          params[:unit_subtype] = 'corner_L'
        end

        validate!(params)

        raw_w = params[:width].to_f
        raw_h = params[:height].to_f
        raw_d = params[:depth].to_f

        if %w[tall_oven tall_storage].include?(params[:unit_subtype].to_s) && raw_h < 1500.0
          raw_h = TALL_DEFAULT_HEIGHT_MM
          params[:height] = raw_h
        end

        width  = raw_w.mm
        height = raw_h.mm
        depth  = raw_d.mm

        if width.to_mm > 5000 || height.to_mm > 5000 || depth.to_mm > 5000
          puts "[Cabinet Neo] ❌ أبعاد ضخمة!"
          return nil
        end

        door_type    = params[:door_type].to_s
        shelves      = params[:shelves].to_i
        cabinet_type = (params[:unit_category] || 'lower').to_s
        unit_subtype = (params[:unit_subtype] || 'standard').to_s
        drawer_heights = params[:drawer_heights] || C::DRAWER_HEIGHTS_DEFAULT
        drawer_box_depths = params[:drawer_box_depths] || C::DRAWER_BOX_DEPTHS_DEFAULT

        oven_drawer = (params[:oven_drawer] || 'none').to_s
        ovb_raw = params[:oven_drawer_box]
        oven_drawer_box = case ovb_raw
                          when false, 'false', '0', 0, nil then false
                          else true
                          end

        if params[:drawer_heights].is_a?(Array) && !params[:drawer_heights].empty?
          drawer_heights = params[:drawer_heights].map { |x| x.to_f }
        end

        if width.to_mm > C::DOUBLE_DOOR_THRESHOLD &&
           %w[single_left single_right].include?(door_type) &&
           (unit_subtype == 'standard' || unit_subtype == 'sink' || unit_subtype == 'tall_storage')
          door_type = 'double'
        end

        place_tr =
          if custom_name
            Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
          elsif defined?(::CabinetNeo::Geometry::UnitArranger)
            begin
              ::CabinetNeo::Geometry::UnitArranger.plan_new_unit(model, width, depth, height, cabinet_type)
            rescue StandardError => e
              puts "[Cabinet Neo] plan_new_unit: #{e.message}"
              Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
            end
          else
            Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
          end

        mats = Materials::MaterialLibrary.prepare_defaults(model)

        ensure_back_panel_ocl(model)
        ensure_sink_mat_ocl(model)

        if custom_name
          unit_name = custom_name
          unit_num  = custom_name[/\d+/].to_i
          unit_num  = next_unit_number(model) if unit_num <= 0
          unit_ar   = unit_num.to_s
        else
          unit_num  = next_unit_number(model)
          unit_ar   = unit_num.to_s
          unit_name = unit_full_name(unit_num, unit_subtype, door_type)
        end

        old_skip = PanelFactory.skip_purge
        PanelFactory.skip_purge = true if skip_purge

        model.start_operation('Cabinet Neo: Create Cabinet', true) if own_operation

        begin
          def_name = skip_purge ? "#{unit_name}_#{Time.now.to_i}" : unit_name

          cab_def = model.definitions.add(def_name)
          cab_def.set_attribute('CabinetNeo', 'generated', true)
          cab_def.set_attribute('CabinetNeo', 'display_name', unit_name)
          cab_def.set_attribute('CabinetNeo', 'unit_category', cabinet_type)
          cab_def.set_attribute('CabinetNeo', 'unit_subtype', unit_subtype)
          cab_def.set_attribute('CabinetNeo', 'unit_number', unit_num)
          cab_def.set_attribute('CabinetNeo', 'cn_sink_unit', unit_subtype == 'sink')
          cab_def.set_attribute('CabinetNeo', 'params', params.to_json)
          cab_def.set_attribute('CabinetNeo', 'drawer_heights', drawer_heights.to_json)
          cab_def.set_attribute('CabinetNeo', 'drawer_box_depths', drawer_box_depths.to_json)
          cab_def.set_attribute('CabinetNeo', 'oven_drawer', oven_drawer)
          cab_def.set_attribute('CabinetNeo', 'oven_drawer_box', oven_drawer_box.to_s)

          if unit_subtype == 'corner_L'
            cab_def.set_attribute('CabinetNeo', 'corner_w_right', params[:corner_w_right].to_f) if params[:corner_w_right]
            cab_def.set_attribute('CabinetNeo', 'corner_w_left',  params[:corner_w_left].to_f)  if params[:corner_w_left]
            cab_def.set_attribute('CabinetNeo', 'corner_d_right', params[:corner_d_right].to_f) if params[:corner_d_right]
            cab_def.set_attribute('CabinetNeo', 'corner_d_left',  params[:corner_d_left].to_f)  if params[:corner_d_left]
          end

          if unit_subtype == 'counter_fixed'
            cab_def.set_attribute('CabinetNeo', 'fixed_side',    (params[:fixed_side] || 'left').to_s)
            cab_def.set_attribute('CabinetNeo', 'counter_width', (params[:counter_width] || 500.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'filler_width',  (params[:filler_width]  || 150.0).to_f)
          end

          if unit_subtype == 'tall_oven'
            cab_def.set_attribute('CabinetNeo', 'tall_micro_door_h',  (params[:tall_micro_door_h]  || 450.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'tall_bottom_h',      (params[:tall_bottom_h]      || 620.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'tall_niche_h',       (params[:tall_niche_h]       || 350.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'tall_oven_niche_h',  (params[:tall_oven_niche_h]  || 600.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'tall_tray_drawer_h', (params[:tall_tray_drawer_h] || 150.0).to_f)
            cab_def.set_attribute('CabinetNeo', 'tall_bottom_type',   (params[:tall_bottom_type]   || 'drawers').to_s)
          end

          if unit_subtype == 'tall_storage'
            params[:ts] = ts_normalize(params[:ts])
            cab_def.set_attribute('CabinetNeo', 'ts_params', params[:ts].to_json)
          end

          activate_dc(cab_def)
          ents = cab_def.entities

          case unit_subtype
          when 'corner_L'
            cw_right = params[:corner_w_right] ? params[:corner_w_right].to_f.mm : C::CORNER_W_RIGHT_DEFAULT.mm
            cw_left  = params[:corner_w_left]  ? params[:corner_w_left].to_f.mm  : C::CORNER_W_LEFT_DEFAULT.mm
            cd_right = params[:corner_d_right] ? params[:corner_d_right].to_f.mm : nil
            cd_left  = params[:corner_d_left]  ? params[:corner_d_left].to_f.mm  : nil
            build_corner_L(ents, cw_left, height, cw_right, mats, unit_ar, custom_edges,
                           cd_left, cd_right)
          when 'counter_fixed'
            fside = (params[:fixed_side] || 'left').to_s
            cw    = params[:counter_width] ? params[:counter_width].to_f : 500.0
            fw    = params[:filler_width]  ? params[:filler_width].to_f  : 150.0
            build_legs_and_plinth(ents, width, height, depth, mats, unit_ar)
            build_counter_fixed_unit(ents, width, height, depth, mats, unit_ar, custom_edges,
                                      fside, cw, fw, shelves)
          when 'tall_oven'
            build_tall_oven_unit(ents, width, height, depth, mats, unit_ar, custom_edges, params)
          when 'tall_storage'
            build_tall_storage_unit(ents, width, height, depth, mats, unit_ar, custom_edges, params, door_type)
          when 'drawers'
            build_legs_and_plinth(ents, width, height, depth, mats, unit_ar)
            drawer_layout = compute_drawer_layout(height, drawer_heights)
            side_notches  = compute_side_notches(drawer_layout)
            build_carcass(ents, width, height, depth, mats, unit_ar, custom_edges,
                          skip_sides: false, side_notches: side_notches)
            build_drawer_stack(ents, width, height, depth, drawer_heights, mats, unit_ar, custom_edges, drawer_box_depths)
          when 'oven'
            build_legs_and_plinth(ents, width, height, depth, mats, unit_ar)
            build_oven_unit(ents, width, height, depth, mats, unit_ar, custom_edges,
                            oven_drawer, oven_drawer_box)
          when 'sink'
            build_legs_and_plinth(ents, width, height, depth, mats, unit_ar)
            build_sink_unit(ents, width, height, depth, mats, unit_ar, custom_edges, door_type)
          else
            build_legs_and_plinth(ents, width, height, depth, mats, unit_ar)
            build_carcass(ents, width, height, depth, mats, unit_ar, custom_edges)
            build_shelves(ents, width, height, depth, shelves, mats, unit_ar, custom_edges)
          end

          case unit_subtype
          when 'oven', 'sink', 'corner_L', 'counter_fixed', 'tall_oven', 'tall_storage'
          when 'standard'
            build_doors(ents, width, height, depth, door_type, mats, unit_ar, custom_edges)
            build_handle(ents, width, height, depth, mats, unit_ar, custom_edges)
          end

          apply_unit_dc_attributes(cab_def, width, height, depth, door_type, shelves, cabinet_type, unit_subtype, drawer_box_depths)

          transform = place_tr
          instance = model.entities.add_instance(cab_def, transform)
          instance.name = unit_name

          assign_unit_tag(instance, cabinet_type)

          wakeup_dc(instance)

          model.selection.clear
          model.selection.add(instance)

          unless skip_zoom
            model.active_view.zoom(instance) if instance.valid?
          end

          model.commit_operation if own_operation
          cleanup_orphan_definitions(model) if own_operation
          instance
        rescue StandardError => e
          model.abort_operation if own_operation
          raise e
        ensure
          PanelFactory.skip_purge = old_skip
        end
      end

      def self.apply_unit_dc_attributes(cab_def, w, h, d, door_type, shelves, cabinet_type = 'lower', unit_subtype = 'standard', drawer_box_depths = nil)
        w_mm    = w.to_mm.round(1)
        d_mm    = d.to_mm.round(1)
        body_h  = h.to_mm.round(1)
        total_h = (h.to_mm + C::PLINTH_HEIGHT).round(1)

        set_dc(cab_def, 'lenx', w_mm)
        set_dc(cab_def, 'leny', d_mm)
        set_dc(cab_def, 'lenz', total_h)
        set_dc(cab_def, 'body_h', body_h, access: 'TEXTBOX', label: 'ارتفاع الجسم (مم)')
        set_dc(cab_def, 'door_swing', door_type,
               access: 'LIST', label: 'اتجاه الباب',
               options: 'right:مفصلي يمين,left:مفصلي شمال,double:بابان')
        set_dc(cab_def, 'shelf_count', shelves, access: 'TEXTBOX', label: 'عدد الأرفف')

        if drawer_box_depths
          set_dc(cab_def, 'drawer_box_depths', drawer_box_depths.to_json,
                 access: 'TEXTBOX', label: 'عمق الصناديق (JSON)')
        end

        type_options = C::CABINET_TYPES.map { |k, v| "#{k}:#{v}" }.join(',')
        set_dc(cab_def, 'cabinet_type', cabinet_type,
               access: 'LIST', label: 'نوع الوحدة', options: type_options)

        subtype_options = C::UNIT_SUBTYPES.map { |k, v| "#{k}:#{v}" }.join(',')
        set_dc(cab_def, 'unit_subtype', unit_subtype,
               access: 'LIST', label: 'النوع الفرعي', options: subtype_options)

        cab_def.set_attribute('dynamic_attributes', '_hasbehaviors', '1')
        cab_def.set_attribute('dynamic_attributes', '_islengths',    '1')
        cab_def.set_attribute('dynamic_attributes', 'name', cab_def.name)
      end

      def self.next_unit_number(model)
        n = model.get_attribute('CabinetNeo', 'next_unit_number', 1)
        model.set_attribute('CabinetNeo', 'next_unit_number', n + 1)
        n
      end

      def self.to_arabic(n)
        n.to_s.chars.map { |c| c =~ /\d/ ? C::ARABIC_DIGITS[c.to_i] : c }.join
      end

      def self.purge_all
        model = Sketchup.active_model
        return unless model
        count_defs = 0; count_inst = 0
        name_pattern = /وحدة|ج\.|م\.|أرضية|ضهر|درفة|رف|مداد|مقبض|قاع|باب|وزر|تاج|رخامة|مراية|حوض|درج|رجل|وش|خلف|شريط|فتحة|خلع|مقطع|هواية|طقم|سدة|كورنر|ثابتة|صندوق|لوح|فاصل/

        model.definitions.to_a.each do |defn|
          next unless defn.get_attribute('CabinetNeo', 'generated', false) || defn.name.to_s =~ name_pattern
          defn.instances.to_a.each do |inst|
            begin
              p = inst.parent
              inst.erase! if p && p.valid?
              count_inst += 1
            rescue StandardError
            end
          end
        end
        model.definitions.to_a.each do |defn|
          next unless defn.get_attribute('CabinetNeo', 'generated', false) || defn.name.to_s =~ name_pattern
          begin
            defn.erase! if defn.valid?
            count_defs += 1
          rescue StandardError
          end
        end

        model.entities.to_a.each do |ent|
          next unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
          should_remove = false
          if ent.is_a?(Sketchup::Group) && ent.get_attribute('CabinetNeo', 'is_countertop', false)
            should_remove = true
          end
          if ent.is_a?(Sketchup::Group) && ent.get_attribute('CabinetNeo', 'is_sink_preview', false)
            should_remove = true
          end
          if ent.is_a?(Sketchup::ComponentInstance) && ent.definition.get_attribute('CabinetNeo', 'is_sink', false)
            should_remove = true
          end
          if should_remove
            begin
              ent.erase! if ent.valid?
            rescue StandardError
            end
          end
        end

        model.set_attribute('CabinetNeo', 'next_unit_number', 1)
        puts "[Cabinet Neo] 🧨 Purged #{count_defs} def(s), #{count_inst} inst(s)."
        model.active_view.invalidate
      end

      def self.diagnose(instance = nil)
        model = Sketchup.active_model
        instance ||= model.selection.first
        return puts('[Cabinet Neo] No instance selected.') unless instance
        return puts('[Cabinet Neo] Not a Component.') unless instance.is_a?(Sketchup::ComponentInstance)

        puts '=' * 60
        puts "[Cabinet Neo DIAGNOSE] #{instance.name}"
        puts '=' * 60

        instance.definition.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
          name = ent.respond_to?(:name) && !ent.name.empty? ? ent.name : ent.definition.name
          mat_names = ent.definition.entities.grep(Sketchup::Face).map(&:material).compact.uniq.map(&:name)
          mat_tag = mat_names.empty? ? '' : " [سطح: #{mat_names.join(', ')}]"
          puts "  📦 #{name.ljust(24)} #{mat_tag}"
        end
        puts '=' * 60
      end

      def self.build_crown(ents, w, h, d, cabinet_type, mats, unit_ar, custom_edges = nil)
      end
      def self.build_legs_and_plinth(ents, w, _h, d, mats, unit_ar)
        model = Sketchup.active_model
        ls = C::LEG_SIZE.mm
        lh = C::LEG_HEIGHT.mm
        li = C::LEG_INSET.mm
        pt = C::PLINTH_THICKNESS.mm
        pr = C::PLINTH_RECESS.mm

        plinth_mat = get_plinth_material(model, mats[:plinth])
        hw_mat     = get_hardware_material(model, mats[:handle])

        leg_y_front_row = (d - pr - pt - ls).to_f
        leg_y_back_row  = li.to_f

        legs_group = ents.add_group
        legs_group.name = "رجول وحدة #{unit_ar}"
        legs_group.set_attribute('CabinetNeo', 'is_legs_group', true)
        lg_ents = legs_group.entities

        [
          [li,            leg_y_front_row, "رجل 1"],
          [w - li - ls,   leg_y_front_row, "رجل 2"],
          [li,            leg_y_back_row,  "رجل 3"],
          [w - li - ls,   leg_y_back_row,  "رجل 4"]
        ].each do |(x, y, label)|
          PanelFactory.component_box(
            lg_ents, x, y, 0, ls, lh, ls,
            name: "#{label} وحدة #{unit_ar}",
            material: hw_mat,
            edge_config: {},
            mats: mats
          )
        end

        plinth_y = d - pr - pt
        PanelFactory.component_box(
          ents, 0, plinth_y, 0, w, lh, pt,
          name: "وزر وحدة #{unit_ar}",
          material: plinth_mat,
          edge_config: resolve_edge_config(:plinth),
          mats: mats
        )

        puts "[Cabinet Neo] 🦵 رجول + وزر لوحدة #{unit_ar}"
      rescue StandardError => e
        puts "[Cabinet Neo] build_legs_and_plinth: #{e.message}"
      end

      def self.build_counter_fixed_unit(ents, w, h, d, mats, unit_ar, custom_edges = nil,
                                         fixed_side = 'left', counter_w_mm = 500.0,
                                         filler_w_mm = 150.0, shelves = 0)
        model = Sketchup.active_model
        t_door  = C::DOOR_THICKNESS.mm
        t_shelf = C::SHELF_THICKNESS.mm

        z0  = C::PLINTH_HEIGHT.mm
        z_t = z0 + h
        gs  = C::DOOR_GAP_SIDE.mm
        gt  = C::DOOR_GAP_TOP.mm
        gb  = C::DOOR_GAP_BOTTOM.mm

        counter_w = counter_w_mm.to_f.mm
        filler_w  = filler_w_mm.to_f.mm
        fixed_w   = counter_w + filler_w

        if w < (fixed_w + 10.mm)
          raise "العرض صغير جداً للجزء الثابت"
        end

        cf_edges = (custom_edges || {}).dup
        cf_edges['front_rail'] = { 'top' => 'white', 'bottom' => 'white' }
        cf_edges['back_rail']  = { 'top' => 'white', 'bottom' => 'white' }

        build_carcass(ents, w, h, d, mats, unit_ar, cf_edges)

        if fixed_side.to_s == 'right'
          counter_x    = w - counter_w
          filler_x     = w - counter_w - filler_w
          hinge_x      = w - fixed_w
          door_x_start = gs
          door_x_end   = w - fixed_w
          hinge_dir    = :minus_x
        else
          counter_x    = 0.0
          filler_x     = counter_w
          hinge_x      = fixed_w
          door_x_start = fixed_w
          door_x_end   = w - gs
          hinge_dir    = :plus_x
        end

        door_w = door_x_end - door_x_start
        door_h = h - gt - gb
        door_z = z0 + gb

        counter_edge_cfg = {
          left:   :white,
          right:  :white,
          top:    :white,
          bottom: :white
        }

        PanelFactory.component_box(
          ents, counter_x, d, z0, counter_w, h, t_door,
          name: "سدة وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: counter_edge_cfg,
          mats: mats
        )

        filler_mat = mats[:door_lac] || mats[:carcass]
        filler_edge_cfg = resolve_edge_config(:door, custom_edges)
        PanelFactory.component_box(
          ents, filler_x, d, z0, filler_w, h, t_door,
          name: "ثابتة وحدة #{unit_ar}",
          material: filler_mat,
          edge_config: filler_edge_cfg,
          mats: mats
        )

        if shelves.to_i > 0
          t  = C::SIDE_THICKNESS.mm
          br = C::BACK_RECESS.mm
          tb = C::BACK_THICKNESS.mm
          iw = w - 2 * t
          shelf_y = br + tb
          shelf_d = d - shelf_y

          if shelf_d > 0
            spacing = (h - 2 * t) / (shelves.to_i + 1)
            shelves.to_i.times do |i|
              z = z0 + t + spacing * (i + 1) - t_shelf / 2.0
              PanelFactory.component_box(
                ents, t, shelf_y, z, iw, t_shelf, shelf_d,
                name: "رف #{i + 1} وحدة #{unit_ar}",
                material: mats[:carcass],
                edge_config: resolve_edge_config(:shelf, custom_edges),
                mats: mats
              )
            end
          end
        end

        if door_w > 0
          door_mat = mats[:door_lac] || mats[:carcass]
          edge_cfg = resolve_edge_config(:door, custom_edges)
          add_hinged_door(ents, hinge_x, d, door_z, door_w, t_door, door_h,
                          hinge_dir, "درفة وحدة #{unit_ar}", door_mat, edge_cfg, mats)
        end

        if door_w > 0
          bar_mat = get_handle_L_material(model, mats[:handle])
          nh_d    = C::HANDLE_NOTCH_DEPTH.mm
          nh_h    = C::HANDLE_NOTCH_HEIGHT.mm
          mat_t   = 3.0.mm

          z_bot   = (z_t - nh_h).to_f
          z_inner = (z_t - nh_h + mat_t).to_f

          y_back  = (d - nh_d).to_f
          y_front = d.to_f
          y_inner = (d - nh_d + mat_t).to_f

          handle_profile = [
            [y_back,  z_bot],
            [y_front, z_bot],
            [y_front, z_inner],
            [y_inner, z_inner],
            [y_inner, z_t.to_f],
            [y_back,  z_t.to_f]
          ]

          PanelFactory.component_profile(
            ents, door_x_start, handle_profile, door_w,
            name: "مقبض وحدة #{unit_ar}",
            material: bar_mat,
            edge_config: resolve_edge_config(:handle, custom_edges),
            mats: mats
          )
        end

        puts "[Cabinet Neo] 🎨 سدة كونتر #{unit_ar}"
      rescue StandardError => e
        puts "[Cabinet Neo] build_counter_fixed_unit: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end

      # =====================================================================
      # ⭐ v79.19: build_side_with_notches — إضافة تطبيق الحاشية (البج الأساسي)
      # =====================================================================
      def self.build_side_with_notches(ents, x, d, t, z0, z_t, notches,
                                        name:, material:, edge_config:, mats:)
        model = Sketchup.active_model
        PanelFactory.force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)
        de = definition.entities

        z_bot = (z0 + t).to_f
        z_top = z_t.to_f
        d_f   = d.to_f
        notch_y_f = (d.to_mm - 20.0).mm.to_f

        pts = []
        pts << [0.0, z_bot]
        pts << [d_f, z_bot]

        sorted = (notches || []).sort_by { |n| n[:bot].to_f }
        merged = []
        sorted.each do |n|
          b0 = n[:bot].to_f
          t0 = n[:top].to_f
          if merged.last && b0 <= merged.last[:top] + 0.5
            merged.last[:top] = [merged.last[:top], t0].max
          else
            merged << { bot: b0, top: t0 }
          end
        end
        merged.each do |n|
          nb = [[n[:bot].to_f, z_bot + 0.5].max, z_top - 0.5].min
          nt = [[n[:top].to_f, nb + 0.5].max, z_top - 0.5].min
          next if nt <= nb

          pts << [d_f,       nb]
          pts << [notch_y_f, nb]
          pts << [notch_y_f, nt]
          pts << [d_f,       nt]
        end

        pts << [d_f, z_top]
        pts << [0.0, z_top]

        pts_3d = pts.map { |y, z| Geom::Point3d.new(0, y, z) }
        face = de.add_face(pts_3d)

        if face
          face.reverse! if face.normal.x < 0
          face.pushpull(t)
        else
          puts "[SIDE] FAIL add_face: #{name}"
          return nil
        end

        if material
          de.grep(Sketchup::Face).each do |f|
            f.material      = material
            f.back_material = material
          end
        end

        # ⭐ v79.19: تطبيق الحاشية على الجوانب (كان ناقص تماماً)
        if edge_config && mats && !edge_config.empty?
          applied = PanelFactory.apply_edge_banding_by_config(definition, edge_config, mats)
        end

        transform = Geom::Transformation.new(Geom::Point3d.new(x, 0, 0))
        instance = ents.add_instance(definition, transform)
        instance.name = name
        instance
      rescue StandardError => e
        puts "[SIDE] FAIL: #{e.message}"
        puts e.backtrace.first(3).join("\n")
        nil
      end

      # =====================================================================
      # ⭐ v79.19: build_drawer_box — يستقبل custom_edges ويستخدم :drawer_box / :drawer_back
      # =====================================================================
      def self.build_drawer_box(ents, w, d, t, z_bottom, dh, mats, unit_ar, idx,
                                bottom_off: 20.0.mm, top_off: 60.0.mm,
                                custom_edges: nil)
        box_t    = 18.0.mm
        bot_t    = 6.0.mm
        fr_t     = 18.0.mm
        front_cl = bottom_off
        top_cl   = top_off
        bot_in   = 18.0.mm
        max_dp   = [d - front_cl - 20.mm, 500.0.mm].min
        box_dp   = [450.0.mm, max_dp].min

        box_w  = w - 2 * t
        box_h  = dh - front_cl - top_cl
        box_h  = [box_h, 80.0.mm].max
        box_z0 = z_bottom + front_cl
        box_y0 = d - box_dp

        return if box_w <= 0 || box_dp <= 0 || box_h <= 0

        # ⭐ إعدادات الحاشية (v79.19)
        box_edge_cfg  = resolve_edge_config(:drawer_box,  custom_edges)
        back_edge_cfg = resolve_edge_config(:drawer_back, custom_edges)

        bg = ents.add_group
        bg.name = "صندوق درج #{idx} وحدة #{unit_ar}"
        bg.set_attribute('CabinetNeo', 'is_drawer_box', true)
        tag_drawer_part(bg, d)
        bg_ents = bg.entities

        # ⭐ وش الصندوق — يستخدم :drawer_box
        PanelFactory.component_box(bg_ents, t + box_t, d - fr_t, box_z0,
          box_w - 2 * box_t, box_h, fr_t,
          name: "وش صندوق #{idx} وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats)

        # القاع (6مم — مش هياخد حاشية لأن السماكة أقل من 18)
        PanelFactory.component_box(bg_ents, t, box_y0, box_z0 + bot_in,
          box_w, bot_t, box_dp,
          name: "قاع درج #{idx} وحدة #{unit_ar}",
          material: mats[:back], edge_config: {}, mats: mats)

        # ⭐ جوانب الصندوق — تستخدم :drawer_box
        PanelFactory.component_box(bg_ents, t, box_y0, box_z0,
          box_t, box_h, box_dp,
          name: "ج.صندوق #{idx} وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats)

        PanelFactory.component_box(bg_ents, t + box_w - box_t, box_y0, box_z0,
          box_t, box_h, box_dp,
          name: "ج.صندوق 2 #{idx} وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats)

        # ⭐ ضهر الصندوق — يستخدم :drawer_back (v79.19)
        PanelFactory.component_box(bg_ents, t + box_t, box_y0, box_z0,
          box_w - 2 * box_t, box_h, box_t,
          name: "ضهر درج #{idx} وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: back_edge_cfg, mats: mats)
      rescue StandardError => e
        puts "[Cabinet Neo] build_drawer_box: #{e.message}"
      end

      def self.build_tall_oven_unit(ents, w, h, d, mats, unit_ar, custom_edges = nil, params = {})
        model = Sketchup.active_model
        t    = C::SIDE_THICKNESS.mm
        tb   = C::BACK_THICKNESS.mm
        ts   = C::SHELF_THICKNESS.mm
        td   = C::DOOR_THICKNESS.mm
        bg   = C::BACK_GROOVE.mm
        br   = C::BACK_RECESS.mm
        gs   = C::DOOR_GAP_SIDE.mm
        gap  = 2.0.mm
        mat_t = 3.0.mm

        z0  = C::PLINTH_HEIGHT.mm
        z_t = z0 + h

        bottom_h       = (params[:tall_bottom_h] || 620.0).to_f.mm
        gap_handle_h   = 30.0.mm
        vent_h         = 100.0.mm
        oven_h         = (params[:tall_oven_niche_h] || 600.0).to_f.mm
        micro_door_h   = (params[:tall_micro_door_h] || 450.0).to_f.mm
        top_lift       = 18.0.mm
        top_grow       = 18.0.mm
        handle_boost   = 10.0.mm
        handle_c_down  = 30.0.mm
        notch_depth    = 20.0.mm
        handle_l_down  = 56.0.mm
        vent_shelf_cut = 20.0.mm
        up_shift       = 13.0.mm
        l_raise        = 30.0.mm
        drawer_gap     = 30.0.mm

        bottom_type = (params[:tall_bottom_type] || 'drawers').to_s
        bottom_type = 'drawers' unless %w[drawer1 drawers door double].include?(bottom_type)
        drawer_bottom = %w[drawer1 drawers].include?(bottom_type)
        drawer_n      = (bottom_type == 'drawer1') ? 1 : 2

        top_min    = 100.0.mm
        micro_h    = micro_door_h + gap
        top_door_h = h - (bottom_h + gap_handle_h + vent_h + oven_h) - micro_h - gap / 2.0
        if top_door_h < top_min
          top_door_h   = top_min
          micro_h      = h - (bottom_h + gap_handle_h + vent_h + oven_h) - top_door_h - gap / 2.0
          micro_h      = 150.0.mm if micro_h < 150.0.mm
          micro_door_h = micro_h - gap
          puts "[Cabinet Neo] ⚠️ الارتفاعات أكبر من ارتفاع الدولاب — درفة الميكروويف اتعدلت لـ #{micro_door_h.to_mm.round} مم"
        end

        z_door_top  = z0 + bottom_h
        z_gap_top   = z_door_top + gap_handle_h
        z_vent_top  = z_gap_top + vent_h
        z_oven_top  = z_vent_top + oven_h
        z_micro_top = z_oven_top + micro_h

        sh1_bot  = z_door_top  - ts - 250.0.mm
        vsh_bot  = z_vent_top  - ts + 17.0.mm + up_shift
        osh_bot  = z_oven_top  - ts + 10.0.mm
        msh_bot  = z_micro_top - ts + 10.0.mm

        handle_h = 30.0.mm + handle_boost
        c_z      = z_gap_top - handle_h - handle_c_down
        c_top    = c_z + handle_h
        l_top    = z_vent_top + l_raise
        l_z      = l_top - C::HANDLE_NOTCH_HEIGHT.mm

        notch_y  = (d.to_mm - notch_depth.to_mm).mm

        iw = w - 2 * t
        door_mat = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:door, custom_edges)
        hw_mat   = get_hardware_material(model, mats[:handle])

        puts "[Cabinet Neo] 🏗️ دولاب فرن v38: bottom=#{bottom_type}"

        # ═══ 1. الرجول + الوزر ═══
        build_legs_and_plinth(ents, w, h, d, mats, unit_ar)

        # ═══ 2. الأرضية ═══
        PanelFactory.component_box(ents, 0, 0, z0, w, t, d,
          name: "أرضية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:floor, custom_edges), mats: mats)

        # ⭐ notch C
        nh_d = C::HANDLE_NOTCH_DEPTH.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm
        notch_y_mm = d.to_mm - nh_d.to_mm
        notch_y = notch_y_mm.mm

        all_notches = []
        unless drawer_bottom
          all_notches << { bot: z_door_top - 25.mm, top: z_door_top - 25.mm + nh_h, depth_y: notch_y }
        end
        all_notches << { bot: l_z, top: l_top, depth_y: notch_y }

        if drawer_bottom
          n = drawer_n
          dhh = bottom_h / n.to_f
          n.times do |i|
            d_top = z_door_top - (i * dhh)
            ft_n   = d_top - (i == 0 ? 0 : drawer_gap / 2.0)
            hz_bot = ft_n - 25.mm
            hz_top = hz_bot + nh_h
            nb = [hz_bot, z0 + t].max
            nt = [hz_top, z_t].min
            if nb < nt - 1.mm
              all_notches << { bot: nb, top: nt, depth_y: notch_y }
            end
          end
        end

        all_notches.sort_by! { |nn| nn[:bot] }
        puts "[Cabinet Neo] 📋 notches (" + all_notches.size.to_s + "): " + all_notches.map { |n| "#{n[:bot].to_mm.round}→#{n[:top].to_mm.round}" }.join(', ')

        # ═══ 4. الجوانب — مع الحاشية الآن (v79.19) ═══
        build_side_with_notches(ents, 0, d, t, z0, z_t, all_notches,
          name: "ج.شمال وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges), mats: mats)
        build_side_with_notches(ents, w - t, d, t, z0, z_t, all_notches,
          name: "ج.يمين وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges), mats: mats)

        # ═══ 5. السقفية — تستخدم :top الآن (v79.19) ═══
        PanelFactory.component_box(ents, t, 0, z_t - t, iw, t, d,
          name: "سقفية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:top, custom_edges), mats: mats)

        # ═══ 6. الضهرية ═══
        back_x = t - bg; back_w = iw + 2 * bg
        PanelFactory.component_box(ents, back_x, br, z0 + t,
          back_w, (z_t - t) - (z0 + t), tb,
          name: "ضهرية وحدة #{unit_ar}", material: mats[:back],
          edge_config: {}, mats: mats)

        # ═══ 7. الفواصل ═══
        # ⭐ فاصل 1 بيتضاف بس لو القسم السفلي درفة (مش أدراج)
        unless drawer_bottom
          PanelFactory.component_box(ents, t, br + tb, sh1_bot, iw, ts, d - br - tb,
            name: "فاصل 1 وحدة #{unit_ar}", material: mats[:carcass],
            edge_config: resolve_edge_config(:shelf, custom_edges), mats: mats)
        end
        PanelFactory.component_box(ents, t, br + tb, vsh_bot,
          iw, ts, d - br - tb - vent_shelf_cut,
          name: "رف هواية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:shelf, custom_edges), mats: mats)
        PanelFactory.component_box(ents, t, br + tb, osh_bot, iw, ts, d - br - tb,
          name: "فاصل فرن وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:shelf, custom_edges), mats: mats)
        PanelFactory.component_box(ents, t, br + tb, msh_bot, iw, ts, d - br - tb,
          name: "فاصل ميكروويف وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:shelf, custom_edges), mats: mats)

        # ═══ 8. القسم السفلي ═══
        if drawer_bottom
          n = drawer_n
          dhh = bottom_h / n.to_f
          n.times do |i|
            d_top = z_door_top - (i * dhh)
            d_bot = d_top - dhh
            ft = d_top - (i == 0 ? 0 : drawer_gap / 2.0)
            fb = d_bot + (i == n - 1 ? 0 : drawer_gap / 2.0)
            fh = ft - fb
            next if fh <= 0

            front = PanelFactory.component_box(ents, gs, d, fb, w - 2 * gs, fh, td,
              name: "واجهة درج #{i + 1} وحدة #{unit_ar}", material: door_mat,
              edge_config: resolve_edge_config(:drawer, custom_edges), mats: mats)
            if front&.valid?
              front.set_attribute('CabinetNeo', 'is_drawer', true)
              front.set_attribute('CabinetNeo', 'drawer_index', i + 1)
              tag_drawer_part(front, d)
            end

            build_handle_C_for_drawer(ents, w, fh, d, fb, mats, unit_ar, i + 1)

            hdl_clear  = 15.0.mm
            lower_clr  = 7.0.mm
            bx_bot_off = (i < n - 1) ? [20.0.mm, (30.0.mm - drawer_gap) + lower_clr].max : 20.0.mm
            bx_top_off = 25.0.mm + hdl_clear
            # ⭐ v79.19: نمرر custom_edges لصناديق الأدراج
            build_drawer_box(ents, w, d, t, fb, fh, mats, unit_ar, i + 1,
                             bottom_off: bx_bot_off, top_off: bx_top_off,
                             custom_edges: custom_edges)
          end
        elsif bottom_type == 'double'
          dw = (w - 2 * gs - gap) / 2.0
          dh = bottom_h
          add_hinged_door(ents, gs, d, z0, dw, td, dh, :plus_x,
            "درفة يمين وحدة #{unit_ar}", door_mat, edge_cfg, mats)
          add_hinged_door(ents, w - gs, d, z0, dw, td, dh, :minus_x,
            "درفة شمال وحدة #{unit_ar}", door_mat, edge_cfg, mats)
          build_handle_C_for_drawer(ents, w, dh, d, z0, mats, unit_ar, 1)
        else
          dh = bottom_h
          add_hinged_door(ents, gs, d, z0, w - 2 * gs, td, dh, :plus_x,
            "درفة سفلية وحدة #{unit_ar}", door_mat, edge_cfg, mats)
          build_handle_C_for_drawer(ents, w, dh, d, z0, mats, unit_ar, 1)
        end

        # ═══ 9. درفة الهواية ═══
        vd_bot = z_gap_top
        vd_top = z_vent_top
        vd_h   = vd_top - vd_bot
        if vd_h > 0
          vent_door = PanelFactory.component_box(ents, gs, d, vd_bot, w - 2 * gs, vd_h, td,
            name: "درفة هواية وحدة #{unit_ar}", material: door_mat,
            edge_config: edge_cfg, mats: mats)
          vent_door.set_attribute('CabinetNeo', 'is_touch', true) if vent_door&.valid?
        end

        # ═══ 11. درفة الميكروويف ═══
        md_bot = z_oven_top + gap / 2.0
        md_top = z_micro_top - gap / 2.0
        md_h = md_top - md_bot
        if md_h > 0
          micro = PanelFactory.component_box(ents, gs, d, md_bot, w - 2 * gs, md_h, td,
            name: "درفة ميكروويف وحدة #{unit_ar}", material: door_mat,
            edge_config: edge_cfg, mats: mats)
          micro.set_attribute('CabinetNeo', 'is_touch', true) if micro&.valid?
        end

        # ═══ 12. الدرفة العلوية ═══
        top_bot = z_micro_top + gap / 2.0 + top_lift - top_grow
        top_top = z_t
        top_h   = top_top - top_bot
        if top_h > 0
          flip = PanelFactory.component_box(ents, gs, d, top_bot, w - 2 * gs, top_h, td,
            name: "درفة علوية قلاب وحدة #{unit_ar}", material: door_mat,
            edge_config: edge_cfg, mats: mats)
          if flip&.valid?
            flip.set_attribute('CabinetNeo', 'is_flip_up', true)
            flip.set_attribute('CabinetNeo', 'is_touch', true)
          end
        end

        # ═══ 13. مقبض L ═══
        bar_l_mat = get_handle_L_material(model, mats[:handle])
        y_front_l = d.to_f
        y_back_l  = (y_front_l - nh_d).to_f
        y_in_l    = (y_back_l + mat_t).to_f
        profile_l = [
          [y_back_l,  l_z.to_f],
          [y_front_l, l_z.to_f],
          [y_front_l, (l_z + mat_t).to_f],
          [y_in_l,    (l_z + mat_t).to_f],
          [y_in_l,    l_top.to_f],
          [y_back_l,  l_top.to_f]
        ]
        PanelFactory.component_profile(ents, 0, profile_l, w,
          name: "مقبض L وحدة #{unit_ar}", material: bar_l_mat,
          edge_config: {}, mats: mats)

        puts "[Cabinet Neo] 🍳 دولاب فرن v38 #{unit_ar} اتبنى (bottom=#{bottom_type})"
      rescue StandardError => e
        puts "[Cabinet Neo] build_tall_oven_unit: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end
      def self.build_corner_L(ents, w1, h, w2, mats, unit_ar, custom_edges = nil, d1 = nil, d2 = nil)
        model = Sketchup.active_model
        t   = C::SIDE_THICKNESS.mm
        tb  = C::BACK_THICKNESS.mm
        ts  = C::SHELF_THICKNESS.mm
        d1  = (d1 || C::CORNER_D_RIGHT_DEFAULT.mm).to_f
        d2  = (d2 || C::CORNER_D_LEFT_DEFAULT.mm).to_f
        z0  = C::PLINTH_HEIGHT.mm
        z_t = z0 + h
        gs  = C::DOOR_GAP_SIDE.mm
        gt  = C::DOOR_GAP_TOP.mm
        gb  = C::DOOR_GAP_BOTTOM.mm
        bg  = C::BACK_GROOVE.mm
        nh_d = C::HANDLE_NOTCH_DEPTH.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm

        top_rail_h  = t
        top_rail_d  = 80.0.mm
        top_recess  = 20.0.mm
        top_z       = z_t - top_rail_h

        PanelFactory.component_L(ents, 0, 0, z0, w1, d1, w2, d2, t,
          name: "أرضية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: { front: :white, right: :white, back: :dark, left: :dark },
          mats: mats)

        back_z_bottom = z0 + t - bg
        back_h        = h - t

        PanelFactory.component_box(ents, t, t, back_z_bottom,
          w1 - 2 * t + bg, back_h, tb,
          name: "ضهر 1 وحدة #{unit_ar}",
          material: mats[:back], edge_config: {}, mats: mats)

        PanelFactory.component_box(ents, t, 0, back_z_bottom,
          tb, back_h, w2 - t + bg,
          name: "ضهر 2 وحدة #{unit_ar}",
          material: mats[:back], edge_config: {}, mats: mats)

        z_notch_top    = z_t.to_f
        z_notch_bottom = (z_notch_top - nh_h).to_f

        right_profile = [
          [0.0,              (z0 + t).to_f],
          [d1.to_f,          (z0 + t).to_f],
          [d1.to_f,          z_notch_bottom],
          [(d1 - nh_d).to_f, z_notch_bottom],
          [(d1 - nh_d).to_f, z_t.to_f],
          [0.0,              z_t.to_f]
        ]
        PanelFactory.component_profile(
          ents, w1 - t, right_profile, t,
          name: "ج.شمال وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )

        left_grp = ents.add_group
        left_grp.name = "ج.يمين وحدة #{unit_ar}"
        left_grp.set_attribute('CabinetNeo', 'generated', true)
        left_grp.set_attribute('CabinetNeo', 'piece_name', "ج.يمين وحدة #{unit_ar}")

        left_profile = [
          [0.0,              (z0 + t).to_f],
          [d2.to_f,          (z0 + t).to_f],
          [d2.to_f,          z_notch_bottom],
          [(d2 - nh_d).to_f, z_notch_bottom],
          [(d2 - nh_d).to_f, z_t.to_f],
          [0.0,              z_t.to_f]
        ]
        PanelFactory.component_profile(
          left_grp.entities, 0, left_profile, t,
          name: "ج.يمين وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )

        rot = Geom::Transformation.rotation(
          Geom::Point3d.new(0, 0, 0),
          Geom::Vector3d.new(0, 0, 1),
          -90.degrees
        )
        tr = Geom::Transformation.translation(Geom::Point3d.new(0, w2, 0))
        left_grp.transformation = tr * rot

        front_mat_map = {
          front_y: 'شريط ابيض مط1',
          back_y:  'شريط ابيض مط1',
          front_x: 'شريط ابيض مط1',
          back_x:  'شريط ابيض مط1'
        }

        fr_a_y = d1 - top_recess - top_rail_d
        fr_a = PanelFactory.component_box(ents, top_rail_d, fr_a_y, top_z,
          w1 - t - top_rail_d, top_rail_h, top_rail_d,
          name: "م.أمامي 1 وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:front_rail, custom_edges), mats: mats)
        apply_face_materials_by_normal(fr_a, front_mat_map)

        fr_b_x = d2 - top_recess - top_rail_d
        fr_b = PanelFactory.component_box(ents, fr_b_x, top_rail_d, top_z,
          top_rail_d, top_rail_h, w2 - t - top_rail_d,
          name: "م.أمامي 2 وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:front_rail, custom_edges), mats: mats)
        apply_face_materials_by_normal(fr_b, front_mat_map)

        br_a = PanelFactory.component_box(ents, 0, 0, top_z,
          w1 - t, top_rail_h, top_rail_d,
          name: "م.خلفي 1 وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:back_rail, custom_edges), mats: mats)
        apply_face_materials_by_normal(br_a, {
          front_y: 'شريط ابيض مط1',
          back_y:  'مفحار1',
          front_x: 'مفحار1',
          back_x:  'مفحار1'
        })

        br_b = PanelFactory.component_box(ents, 0, top_rail_d, top_z,
          top_rail_d, top_rail_h, w2 - t - top_rail_d,
          name: "م.خلفي 2 وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:back_rail, custom_edges), mats: mats)
        apply_face_materials_by_normal(br_b, {
          front_y: 'مفحار1',
          back_y:  'مفحار1',
          front_x: 'شريط ابيض مط1',
          back_x:  'مفحار1'
        })

        vert_z_bottom = z0 + t
        vert_h        = top_z - vert_z_bottom
        vr = PanelFactory.component_box(ents, 0, 0, vert_z_bottom,
          t, vert_h, top_rail_d,
          name: "م.رأسي وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:back_rail, custom_edges), mats: mats)
        apply_face_materials_by_normal(vr, {
          front_y: 'شريط ابيض مط1',
          back_y:  'مفحار1',
          front_x: 'كونتر',
          back_x:  'كونتر'
        })

        shelf_ox  = t + tb
        shelf_oy  = t + tb
        shelf_out = w1 - t
        shelf_w1  = shelf_out - shelf_ox
        shelf_w2  = (w2 - t) - shelf_oy
        shelf_d1  = d1 - t - tb
        shelf_d2  = d2 - t - tb
        shelf_z_bottom = z0 + t + (h - 2 * t) * 0.45

        if shelf_w1 > 0 && shelf_d1 > 0 && shelf_w2 > 0 && shelf_d2 > 0
          PanelFactory.component_L(ents, shelf_ox, shelf_oy, shelf_z_bottom,
            shelf_w1, shelf_d1, shelf_w2, shelf_d2, ts,
            name: "رف وحدة #{unit_ar}", material: mats[:carcass],
            edge_config: { front: :white, right: :white, back: :dark, left: :dark },
            mats: mats)
        end

        door_mat = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:door, custom_edges)
        door_h   = h - gt - gb
        door_z   = z0 + gb

        door_A_x = d2 + t + gs
        door_A_w = (w1 - 1.mm) - door_A_x
        if door_A_w > 0
          add_hinged_door(ents, w1 - 1.mm, d1, door_z,
            door_A_w, t, door_h, :minus_x,
            "درفة A وحدة #{unit_ar}", door_mat, edge_cfg, mats,
            max_angle: CORNER_DOOR_OPEN_ANGLE)
        end

        door_B_y = d1 + 1.mm
        door_B_d = (w2 - 1.mm) - door_B_y
        if door_B_d > 0
          add_hinged_door(ents, d2 + t, w2 - 1.mm, door_z,
            door_B_d, t, door_h, :minus_x,
            "درفة B وحدة #{unit_ar}", door_mat, edge_cfg, mats,
            along_y: true, open_sign: 1, max_angle: CORNER_DOOR_OPEN_ANGLE)
        end

        hw_mat = get_hardware_material(model, mats[:handle])
        ls = C::LEG_SIZE.mm
        lh = C::LEG_HEIGHT.mm
        li = C::LEG_INSET.mm
        pr_leg = C::PLINTH_RECESS.mm + C::PLINTH_THICKNESS.mm

        legs_group = ents.add_group
        legs_group.name = "رجول وحدة #{unit_ar}"
        legs_group.set_attribute('CabinetNeo', 'is_legs_group', true)
        lg = legs_group.entities

        leg_front_y = d1 - pr_leg - ls
        leg_front_x = d2 - pr_leg - ls

        [
          [li,               li,               "رجل 1"],
          [w1 - li - ls,     li,               "رجل 2"],
          [li,               w2 - li - ls,     "رجل 3"],
          [leg_front_x,      w2 - li - ls,     "رجل 4"],
          [w1 - li - ls,     leg_front_y,      "رجل 5"],
          [leg_front_x,      leg_front_y,      "رجل 6"]
        ].each do |(x, y, label)|
          PanelFactory.component_box(lg, x, y, 0, ls, lh, ls,
            name: "#{label} وحدة #{unit_ar}",
            material: hw_mat, edge_config: {}, mats: mats)
        end

        plinth_mat = get_plinth_material(model, mats[:plinth])
        ph = C::PLINTH_HEIGHT.mm
        pt = C::PLINTH_THICKNESS.mm
        pr = C::PLINTH_RECESS.mm

        plinth_a_x = d2 - pr - pt
        plinth_a_y = d1 - pr - pt
        plinth_a_w = w1 - plinth_a_x
        plinth_a_d = pt

        if plinth_a_w > 0
          PanelFactory.component_box(ents, plinth_a_x, plinth_a_y, 0,
            plinth_a_w, ph, plinth_a_d,
            name: "وزر 1 وحدة #{unit_ar}",
            material: plinth_mat,
            edge_config: resolve_edge_config(:plinth, custom_edges), mats: mats)
        end

        plinth_b_x = d2 - pr - pt
        plinth_b_y = d1 - pr - pt
        plinth_b_w = pt
        plinth_b_d = w2 - plinth_b_y

        if plinth_b_d > 0
          PanelFactory.component_box(ents, plinth_b_x, plinth_b_y, 0,
            plinth_b_w, ph, plinth_b_d,
            name: "وزر 2 وحدة #{unit_ar}",
            material: plinth_mat,
            edge_config: resolve_edge_config(:plinth, custom_edges), mats: mats)
        end

        if door_A_w > 0
          handle_a_x = d2 - nh_d
          handle_a_w = w1 - handle_a_x
          build_handle_L_on_face_Y(ents, handle_a_x, handle_a_w,
                                    d1, z_t, mats, unit_ar, 1)
        end

        if door_B_d > 0
          handle_b_y = d1
          handle_b_w = w2 - handle_b_y
          build_handle_L_on_face_X(ents, handle_b_y, handle_b_w,
                                    d2, z_t, mats, unit_ar, 2)
        end

        puts "[Cabinet Neo] 🏠 كورنر L #{unit_ar} (w1=#{w1.to_mm.round} w2=#{w2.to_mm.round} d1=#{d1.to_mm.round} d2=#{d2.to_mm.round})"
      rescue StandardError => e
        puts "[Cabinet Neo] build_corner_L: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end

      def self.build_handle_L_on_face_Y(ents, x_start, w, y_pos, z_top, mats, unit_ar, idx)
        model   = Sketchup.active_model
        bar_mat = get_handle_L_material(model, mats[:handle])
        nh_d    = C::HANDLE_NOTCH_DEPTH.mm
        nh_h    = C::HANDLE_NOTCH_HEIGHT.mm
        mat_t   = 3.0.mm

        z_bot   = (z_top - nh_h).to_f
        z_inner = (z_bot + mat_t).to_f
        y_front = y_pos.to_f
        y_back  = (y_front - nh_d).to_f
        y_inner = (y_back + mat_t).to_f

        profile = [
          [y_back,  z_bot],
          [y_front, z_bot],
          [y_front, z_inner],
          [y_inner, z_inner],
          [y_inner, z_top.to_f],
          [y_back,  z_top.to_f]
        ]

        PanelFactory.component_profile(
          ents, x_start, profile, w,
          name: "مقبض #{idx} وحدة #{unit_ar}",
          material: bar_mat,
          edge_config: {}, mats: mats
        )
      end

      def self.build_handle_L_on_face_X(ents, y_start, w, x_pos, z_top, mats, unit_ar, idx)
        model   = Sketchup.active_model
        bar_mat = get_handle_L_material(model, mats[:handle])
        nh_d    = C::HANDLE_NOTCH_DEPTH.mm
        nh_h    = C::HANDLE_NOTCH_HEIGHT.mm
        mat_t   = 3.0.mm

        z_bot   = (z_top - nh_h).to_f
        z_inner = (z_bot + mat_t).to_f
        y_back  = (-nh_d).to_f
        y_front = 0.0
        y_inner = (y_back + mat_t).to_f

        profile = [
          [y_back,  z_bot],
          [y_front, z_bot],
          [y_front, z_inner],
          [y_inner, z_inner],
          [y_inner, z_top.to_f],
          [y_back,  z_top.to_f]
        ]

        grp = ents.add_group
        grp.name = "مقبض #{idx} وحدة #{unit_ar}"

        PanelFactory.component_profile(
          grp.entities, 0, profile, w,
          name: "مقبض #{idx} وحدة #{unit_ar}",
          material: bar_mat, edge_config: {}, mats: mats)

        rot = Geom::Transformation.rotation(Geom::Point3d.new(0,0,0), Geom::Vector3d.new(0,0,1), -90.degrees)
        tr  = Geom::Transformation.translation(Geom::Point3d.new(x_pos, y_start + w, 0))
        grp.transformation = tr * rot
      end

      def self.build_sink_unit(ents, w, h, d, mats, unit_ar, custom_edges = nil, door_type = 'double')
        model = Sketchup.active_model
        sink_mat = get_sink_material(model) || mats[:carcass]

        t    = C::SINK_THICKNESS.mm
        brh  = C::BACK_RAIL_HEIGHT.mm
        brt  = C::SINK_THICKNESS.mm
        rd   = C::TOP_RAIL_DEPTH.mm
        frr  = C::FRONT_RAIL_RECESS.mm
        nh_d = C::HANDLE_NOTCH_DEPTH.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm

        iw  = w - 2 * t
        z0  = C::PLINTH_HEIGHT.mm
        z_t = h + z0

        PanelFactory.component_box(
          ents, 0, 0, z0, w, t, d,
          name: "أرضية وحدة #{unit_ar}",
          material: sink_mat,
          edge_config: resolve_edge_config(:floor, custom_edges),
          mats: mats
        )

        right_profile = [
          [0.0, (z0 + t).to_f], [d.to_f, (z0 + t).to_f],
          [d.to_f, (z_t - nh_h).to_f], [(d - nh_d).to_f, (z_t - nh_h).to_f],
          [(d - nh_d).to_f, z_t.to_f], [0.0, z_t.to_f]
        ]
        PanelFactory.component_profile(
          ents, 0, right_profile, t,
          name: "ج.شمال وحدة #{unit_ar}",
          material: sink_mat,
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )
        PanelFactory.component_profile(
          ents, w - t, right_profile, t,
          name: "ج.يمين وحدة #{unit_ar}",
          material: sink_mat,
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, 0, z_t - brh, iw, brh, brt,
          name: "م.خلفي وحدة #{unit_ar}",
          material: sink_mat,
          edge_config: resolve_edge_config(:back_rail, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, d - frr - brt, z_t - rd, iw, rd, brt,
          name: "م.أمامي وحدة #{unit_ar}",
          material: sink_mat,
          edge_config: resolve_edge_config(:front_rail, custom_edges),
          mats: mats
        )

        build_doors(ents, w, h, d, door_type, mats, unit_ar, custom_edges)
        build_handle(ents, w, h, d, mats, unit_ar, custom_edges)

        puts "[Cabinet Neo] 🚰 حوض #{unit_ar}"
      rescue StandardError => e
        puts "[Cabinet Neo] build_sink_unit: #{e.message}"
      end

      def self.build_oven_unit(ents, w, h, d, mats, unit_ar, custom_edges = nil, oven_drawer = 'none', oven_drawer_box = true)
        t    = C::SIDE_THICKNESS.mm
        ts   = C::SHELF_THICKNESS.mm
        brh  = C::BACK_RAIL_HEIGHT.mm
        brt  = C::BACK_RAIL_THICKNESS.mm
        rd   = C::TOP_RAIL_DEPTH.mm
        frr  = C::FRONT_RAIL_RECESS.mm
        nh_d = C::HANDLE_NOTCH_DEPTH.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm
        gt   = C::DOOR_GAP_TOP.mm
        drawer_h = OVEN_DRAWER_FRONT_H.mm

        with_box = case oven_drawer_box
                   when false, 'false', '0', 0, nil then false
                   else true
                   end

        z0  = C::PLINTH_HEIGHT.mm
        z_t = h + z0
        iw  = w - 2 * t

        has_top = (oven_drawer.to_s == 'above')
        has_bot = (oven_drawer.to_s == 'below')
        has_drawer = has_top || has_bot

        drawer_top    = nil
        drawer_bottom = nil
        shelf_z       = nil

        if has_top
          drawer_top    = z_t - gt
          drawer_bottom = drawer_top - drawer_h
        elsif has_bot
          drawer_bottom = z0
          drawer_top    = drawer_bottom + drawer_h
          shelf_z       = drawer_top
        end

        PanelFactory.component_box(
          ents, 0, 0, z0, w, t, d,
          name: "أرضية وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:floor, custom_edges),
          mats: mats
        )

        notches = [[(z_t - nh_h).to_f, z_t.to_f]]

        side_profile = []
        side_profile << [0.0, (z0 + t).to_f]
        side_profile << [d.to_f, (z0 + t).to_f]

        notches.each do |(bz, tz)|
          side_profile << [d.to_f, bz]
          side_profile << [(d - nh_d).to_f, bz]
          side_profile << [(d - nh_d).to_f, tz]
          side_profile << [d.to_f, tz] if tz < z_t.to_f - 0.5
        end

        unless side_profile.last[1] > z_t.to_f - 0.5
          side_profile << [d.to_f, z_t.to_f]
        end
        side_profile << [0.0, z_t.to_f]

        PanelFactory.component_profile(
          ents, 0, side_profile, t,
          name: "ج.شمال وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )
        PanelFactory.component_profile(
          ents, w - t, side_profile, t,
          name: "ج.يمين وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, 0, z_t - brh, iw, brh, brt,
          name: "م.خلفي وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:back_rail, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, d - frr - brt, z_t - rd, iw, rd, brt,
          name: "م.أمامي وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:front_rail, custom_edges),
          mats: mats
        )

        if has_bot && shelf_z
          shelf_d = d.to_f
          shelf_z_actual = (shelf_z - ts).to_f
          PanelFactory.component_box(
            ents, t, 0, shelf_z_actual, iw, ts, shelf_d,
            name: "رف وحدة #{unit_ar}",
            material: mats[:carcass],
            edge_config: resolve_edge_config(:shelf, custom_edges),
            mats: mats
          )
        end

        unless has_top
          build_handle(ents, w, h, d, mats, unit_ar, custom_edges)
        end

        if has_drawer
          if has_top
            build_oven_drawer(ents, w, d, drawer_bottom, drawer_h,
                              mats, unit_ar, custom_edges, :top, with_box)
          else
            build_oven_drawer(ents, w, d, drawer_bottom, drawer_h,
                              mats, unit_ar, custom_edges, :bottom, with_box)
          end
        end

        puts "[Cabinet Neo] 🔥 فرن #{unit_ar} | درج: #{oven_drawer}"
      rescue StandardError => e
        puts "[Cabinet Neo] build_oven_unit: #{e.message}"
      end

      def self.build_oven_drawer(ents, w, d, z_bottom, dh, mats, unit_ar, custom_edges, position, with_box, with_vent = false)
        t = C::SIDE_THICKNESS.mm
        front_t = C::DOOR_THICKNESS.mm
        box_t = C::DRAWER_BOX_THICKNESS.mm
        bot_t = C::DRAWER_BOTTOM_THICK.mm
        bot_in = C::DRAWER_BOTTOM_INSET.mm
        box_fr = C::DRAWER_BOX_FRONT_THICK.mm
        front_cl = C::DRAWER_FRONT_CLEAR.mm
        top_cl = C::DRAWER_TOP_CLEAR.mm
        box_h_base = C::DRAWER_BOX_HEIGHT.mm
        max_dp = [d - C::DRAWER_FRONT_CLEAR.mm - 20.mm, C::DRAWER_BOX_DEPTH_MAX.mm].min
        min_dp = C::DRAWER_BOX_DEPTH_MIN.mm
        box_dp = C::DRAWER_BOX_DEPTH.mm
        box_dp = [box_dp, max_dp].min
        box_dp = [box_dp, min_dp].max

        door_mat = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:drawer, custom_edges)
        box_edge_cfg = resolve_edge_config(:drawer_box, custom_edges)

        front_w = w - 2 * C::DOOR_GAP_SIDE.mm

        front = PanelFactory.component_box(
          ents, C::DOOR_GAP_SIDE.mm, d, z_bottom, front_w, dh, front_t,
          name: "واجهة درج وحدة #{unit_ar}",
          material: door_mat, edge_config: edge_cfg, mats: mats
        )
        if front && front.valid?
          front.set_attribute('CabinetNeo', 'is_drawer', true)
          tag_drawer_part(front, d)
        end

        if position == :top
          build_handle_L_for_drawer(ents, w, dh, d, z_bottom, mats, unit_ar, 1)
        end

        return unless with_box

        box_w  = w - 2 * t
        box_z0 = z_bottom + front_cl
        box_y0 = d - box_dp

        box_h_max = dh - front_cl - top_cl
        box_h_max = [box_h_max, BOX_H_MIN_HARD.mm].max
        box_h_fixed = [box_h_base, box_h_max].min
        box_h_fixed = [box_h_fixed, BOX_H_MIN_HARD.mm].max

        return if box_w <= 0 || box_dp <= 0 || box_h_fixed <= 0

        bg = ents.add_group
        bg.name = "صندوق درج وحدة #{unit_ar}"
        tag_drawer_part(bg, d)
        bg_ents = bg.entities

        PanelFactory.component_box(
          bg_ents, t + box_t, d - box_fr, box_z0,
          box_w - 2 * box_t, box_h_fixed, box_fr,
          name: "وش صندوق وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
        )

        PanelFactory.component_box(
          bg_ents, t, box_y0, box_z0 + bot_in,
          box_w, bot_t, box_dp,
          name: "قاع درج وحدة #{unit_ar}",
          material: mats[:back], edge_config: {}, mats: mats
        )

        PanelFactory.component_box(
          bg_ents, t, box_y0, box_z0,
          box_t, box_h_fixed, box_dp,
          name: "ج.صندوق وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
        )

        PanelFactory.component_box(
          bg_ents, t + box_w - box_t, box_y0, box_z0,
          box_t, box_h_fixed, box_dp,
          name: "ج.صندوق 2 وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
        )

        PanelFactory.component_box(
          bg_ents, t + box_t, box_y0, box_z0,
          box_w - 2 * box_t, box_h_fixed, box_t,
          name: "ضهر درج وحدة #{unit_ar}",
          material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
        )
      end

      def self.build_drawer_stack(ents, w, h, d, drawer_heights, mats, unit_ar, custom_edges = nil, drawer_box_depths = nil)
        t    = C::SIDE_THICKNESS.mm
        front_t  = C::DOOR_THICKNESS.mm
        box_t    = C::DRAWER_BOX_THICKNESS.mm
        bot_t    = C::DRAWER_BOTTOM_THICK.mm
        bot_in   = C::DRAWER_BOTTOM_INSET.mm
        box_fr   = C::DRAWER_BOX_FRONT_THICK.mm
        front_cl = C::DRAWER_FRONT_CLEAR.mm
        top_cl   = C::DRAWER_TOP_CLEAR.mm

        box_h_base = C::DRAWER_BOX_HEIGHT.mm
        max_dp = [d - C::DRAWER_FRONT_CLEAR.mm - 20.mm, C::DRAWER_BOX_DEPTH_MAX.mm].min
        min_dp = C::DRAWER_BOX_DEPTH_MIN.mm

        drawer_data = compute_drawer_layout(h, drawer_heights)
        return if drawer_data.empty?

        door_mat = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:drawer, custom_edges)
        box_edge_cfg = resolve_edge_config(:drawer_box, custom_edges)
        back_edge_cfg = resolve_edge_config(:drawer_back, custom_edges)

        drawer_data.each do |dd|
          i = dd[:index]
          dh = dd[:dh]
          current_bottom = dd[:bottom]
          is_top = dd[:is_top]

          if drawer_box_depths && drawer_box_depths[i]
            box_dp_i = drawer_box_depths[i].to_f.mm
          else
            box_dp_i = C::DRAWER_BOX_DEPTH.mm
          end
          box_dp_i = [box_dp_i, max_dp].min
          box_dp_i = [box_dp_i, min_dp].max

          box_h_max = dh - front_cl - top_cl
          box_h_max = [box_h_max, BOX_H_MIN_HARD.mm].max
          box_h_fixed = [box_h_base, box_h_max].min
          box_h_fixed = [box_h_fixed, BOX_H_MIN_HARD.mm].max

          front_w = w - 2 * C::DOOR_GAP_SIDE.mm
          draw_num = i + 1

          if BUILD_DRAWER_FRONTS
            front = PanelFactory.component_box(
              ents, C::DOOR_GAP_SIDE.mm, d, current_bottom, front_w, dh, front_t,
              name: "واجهة درج #{draw_num} وحدة #{unit_ar}",
              material: door_mat,
              edge_config: edge_cfg,
              mats: mats
            )
            if front && front.valid?
              front.set_attribute('CabinetNeo', 'is_drawer', true)
              front.set_attribute('CabinetNeo', 'drawer_index', draw_num)
              tag_drawer_part(front, d)
            end

            if is_top
              build_handle_L_for_drawer(ents, w, dh, d, current_bottom, mats, unit_ar, draw_num)
            else
              build_handle_C_for_drawer(ents, w, dh, d, current_bottom, mats, unit_ar, draw_num)
            end
          end

          box_w  = w - 2 * t
          box_z0 = current_bottom + front_cl
          box_y0 = d - box_dp_i

          next if box_w <= 0 || box_dp_i <= 0 || box_h_fixed <= 0

          bg = ents.add_group
          bg.name = "صندوق درج #{draw_num} وحدة #{unit_ar}"
          tag_drawer_part(bg, d)
          bg_ents = bg.entities

          PanelFactory.component_box(
            bg_ents, t + box_t, d - box_fr, box_z0,
            box_w - 2 * box_t, box_h_fixed, box_fr,
            name: "وش صندوق درج #{draw_num} وحدة #{unit_ar}",
            material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
          )

          PanelFactory.component_box(
            bg_ents, t, box_y0, box_z0 + bot_in,
            box_w, bot_t, box_dp_i,
            name: "قاع درج #{draw_num} وحدة #{unit_ar}",
            material: mats[:back], edge_config: {}, mats: mats
          )

          PanelFactory.component_box(
            bg_ents, t, box_y0, box_z0,
            box_t, box_h_fixed, box_dp_i,
            name: "ج.صندوق درج #{draw_num} وحدة #{unit_ar}",
            material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
          )

          PanelFactory.component_box(
            bg_ents, t + box_w - box_t, box_y0, box_z0,
            box_t, box_h_fixed, box_dp_i,
            name: "ج.صندوق درج #{draw_num} ب وحدة #{unit_ar}",
            material: mats[:carcass], edge_config: box_edge_cfg, mats: mats
          )

          PanelFactory.component_box(
            bg_ents, t + box_t, box_y0, box_z0,
            box_w - 2 * box_t, box_h_fixed, box_t,
            name: "ضهر درج #{draw_num} وحدة #{unit_ar}",
            material: mats[:carcass], edge_config: back_edge_cfg, mats: mats
          )
        end

        puts "[Cabinet Neo] 🗄️  #{drawer_data.size} أدراج في وحدة #{unit_ar}"
      rescue StandardError => e
        puts "[Cabinet Neo] build_drawer_stack: #{e.message}"
      end

      def self.build_handle_L_for_drawer(ents, w, dh, d, z_bottom, mats, unit_ar, idx)
        model = Sketchup.active_model
        bar_mat = get_handle_L_material(model, mats[:handle])
        nh_d  = C::HANDLE_NOTCH_DEPTH.mm
        nh_h  = C::HANDLE_NOTCH_HEIGHT.mm
        mat_t = 3.0.mm
        drop  = 25.0.mm

        z_bot   = (z_bottom + dh - drop).to_f
        z_top   = (z_bot + nh_h).to_f
        y_back  = (d - nh_d).to_f
        y_front = d.to_f
        y_inner = (y_back + mat_t).to_f
        z_inner = (z_bot + mat_t).to_f

        profile = [
          [y_back,  z_bot],
          [y_front, z_bot],
          [y_front, z_inner],
          [y_inner, z_inner],
          [y_inner, z_top],
          [y_back,  z_top]
        ]

        PanelFactory.component_profile(ents, 0, profile, w,
          name: "مقبض درج #{idx} وحدة #{unit_ar}",
          material: bar_mat, edge_config: {}, mats: mats)
      end

      def self.build_handle_C_for_drawer(ents, w, dh, d, z_bottom, mats, unit_ar, idx)
        model = Sketchup.active_model
        bar_mat = get_handle_C_material(model, mats[:handle])
        nh_d  = C::HANDLE_NOTCH_DEPTH.mm
        nh_h  = C::HANDLE_NOTCH_HEIGHT.mm
        mat_t = 3.0.mm
        raise_up = 30.0.mm

        z_top = (z_bottom + dh + raise_up).to_f
        z_bot = (z_top - nh_h).to_f
        y_back  = (d - nh_d).to_f
        y_front = d.to_f
        y_inner = (y_back + mat_t).to_f

        z_inner_bot = (z_bot + mat_t).to_f
        z_inner_top = (z_top - mat_t).to_f

        profile = [
          [y_back,  z_bot],
          [y_front, z_bot],
          [y_front, z_inner_bot],
          [y_inner, z_inner_bot],
          [y_inner, z_inner_top],
          [y_front, z_inner_top],
          [y_front, z_top],
          [y_back,  z_top]
        ]

        PanelFactory.component_profile(ents, 0, profile, w,
          name: "مقبض C درج #{idx} وحدة #{unit_ar}",
          material: bar_mat, edge_config: {}, mats: mats)
      end

      def self.build_handle(ents, w, h, d, mats, unit_ar, custom_edges = nil)
        model = Sketchup.active_model
        bar_mat = get_handle_L_material(model, mats[:handle])
        nh_d  = C::HANDLE_NOTCH_DEPTH.mm
        nh_h  = C::HANDLE_NOTCH_HEIGHT.mm
        mat_t = 3.0.mm
        z0 = C::PLINTH_HEIGHT.mm
        z_t = h + z0

        y_back  = (d - nh_d).to_f
        y_front = d.to_f
        y_inner = (d - nh_d + mat_t).to_f
        z_bot   = (z_t - nh_h).to_f
        z_inner = (z_t - nh_h + mat_t).to_f

        profile = [
          [y_back,  z_bot],
          [y_front, z_bot],
          [y_front, z_inner],
          [y_inner, z_inner],
          [y_inner, z_t.to_f],
          [y_back,  z_t.to_f]
        ]
        PanelFactory.component_profile(
          ents, 0, profile, w,
          name: "مقبض وحدة #{unit_ar}",
          material: bar_mat,
          edge_config: resolve_edge_config(:handle, custom_edges),
          mats: mats
        )
      end

      def self.build_plinth(ents, w, _h, d, mats, unit_ar, custom_edges = nil)
        model = Sketchup.active_model
        bar_mat = get_plinth_material(model, mats[:plinth])
        pt = C::PLINTH_THICKNESS.mm
        ph = C::PLINTH_HEIGHT.mm
        pr = C::PLINTH_RECESS.mm

        PanelFactory.component_box(
          ents, 0, d - pr - pt, 0, w, ph, pt,
          name: "وزر وحدة #{unit_ar}",
          material: bar_mat,
          edge_config: resolve_edge_config(:plinth, custom_edges),
          mats: mats
        )
      end

      def self.build_carcass(ents, w, h, d, mats, unit_ar, custom_edges = nil, skip_sides: false, side_notches: nil)
        t    = C::SIDE_THICKNESS.mm
        tb   = C::BACK_THICKNESS.mm
        br   = C::BACK_RECESS.mm
        bg   = C::BACK_GROOVE.mm
        rd   = C::TOP_RAIL_DEPTH.mm
        frr  = C::FRONT_RAIL_RECESS.mm
        brh  = C::BACK_RAIL_HEIGHT.mm
        brt  = C::BACK_RAIL_THICKNESS.mm
        nh_d = C::HANDLE_NOTCH_DEPTH.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm

        iw  = w - 2 * t
        z0  = C::PLINTH_HEIGHT.mm
        z_t = h + z0

        PanelFactory.component_box(
          ents, 0, 0, z0, w, t, d,
          name: "أرضية وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:floor, custom_edges),
          mats: mats
        )

        unless skip_sides
          profile_pts = build_side_profile_pts(z0, z_t, d, t, nh_d, nh_h, side_notches)

          PanelFactory.component_profile(
            ents, 0, profile_pts, t,
            name: "ج.شمال وحدة #{unit_ar}",
            material: mats[:carcass],
            edge_config: resolve_edge_config(:side, custom_edges),
            mats: mats
          )
          PanelFactory.component_profile(
            ents, w - t, profile_pts, t,
            name: "ج.يمين وحدة #{unit_ar}",
            material: mats[:carcass],
            edge_config: resolve_edge_config(:side, custom_edges),
            mats: mats
          )
        end

        back_x = t - bg; back_w = iw + 2 * bg
        back_z = z0 + t - bg; back_h = z_t - back_z
        PanelFactory.component_box(
          ents, back_x, br, back_z, back_w, back_h, tb,
          name: "ضهر وحدة #{unit_ar}",
          material: mats[:back],
          edge_config: resolve_edge_config(:back, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, 0, z_t - brh, iw, brh, brt,
          name: "م.خلفي وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:back_rail, custom_edges),
          mats: mats
        )

        PanelFactory.component_box(
          ents, t, d - frr - brt, z_t - rd, iw, rd, brt,
          name: "م.أمامي وحدة #{unit_ar}",
          material: mats[:carcass],
          edge_config: resolve_edge_config(:front_rail, custom_edges),
          mats: mats
        )
      end

      def self.build_shelves(ents, w, h, d, shelves, mats, unit_ar, custom_edges = nil)
        return if shelves <= 0
        t  = C::SIDE_THICKNESS.mm
        ts = C::SHELF_THICKNESS.mm
        br = C::BACK_RECESS.mm
        tb = C::BACK_THICKNESS.mm
        iw = w - 2 * t
        ih = h - 2 * t
        shelf_y = br + tb
        shelf_d = d - shelf_y
        return if shelf_d <= 0

        z0 = C::PLINTH_HEIGHT.mm
        spacing = ih / (shelves + 1)

        shelves.times do |i|
          z = z0 + t + spacing * (i + 1) - ts / 2.0
          PanelFactory.component_box(
            ents, t, shelf_y, z, iw, ts, shelf_d,
            name: "رف #{i + 1} وحدة #{unit_ar}",
            material: mats[:carcass],
            edge_config: resolve_edge_config(:shelf, custom_edges),
            mats: mats
          )
        end
      end

      def self.build_doors(ents, w, h, d, door_type, mats, unit_ar, custom_edges = nil)
        td  = C::DOOR_THICKNESS.mm
        gs  = C::DOOR_GAP_SIDE.mm
        gm  = C::DOOR_GAP_MIDDLE.mm
        gt  = C::DOOR_GAP_TOP.mm

        z0 = C::PLINTH_HEIGHT.mm
        door_h = h - gt
        door_z = z0

        door_material = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:door, custom_edges)

        case door_type.to_s
        when 'single_right'
          add_hinged_door(ents, gs, d, door_z, w - 2 * gs, td, door_h,
                          :plus_x, "درفة وحدة #{unit_ar}", door_material, edge_cfg, mats)
        when 'single_left'
          add_hinged_door(ents, w - gs, d, door_z, w - 2 * gs, td, door_h,
                          :minus_x, "درفة وحدة #{unit_ar}", door_material, edge_cfg, mats)
        when 'double'
          door_w = (w - 2 * gs - gm) / 2.0
          add_hinged_door(ents, gs, d, door_z, door_w, td, door_h,
                          :plus_x, "درفة يمين وحدة #{unit_ar}", door_material, edge_cfg, mats)
          add_hinged_door(ents, w - gs, d, door_z, door_w, td, door_h,
                          :minus_x, "درفة شمال وحدة #{unit_ar}", door_material, edge_cfg, mats)
        end
      end

      def self.add_hinged_door(ents, hinge_x, hinge_y, hinge_z,
                                door_w, td, door_h, extend_dir, name,
                                material, edge_config = nil, mats = nil,
                                along_y: false, open_sign: nil, max_angle: DOOR_OPEN_ANGLE)
        open_sign ||= (extend_dir == :minus_x) ? -1 : 1
        model = Sketchup.active_model
        PanelFactory.force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)
        definition.set_attribute('CabinetNeo', 'is_door', true)
        definition.set_attribute('CabinetNeo', 'open_angle', max_angle.to_f)
        definition.set_attribute('CabinetNeo', 'hinge_direction', open_sign < 0 ? 'minus_x' : 'plus_x')

        activate_dc(definition)

        x0 = (extend_dir == :minus_x) ? -door_w : 0.0
        x1 = (extend_dir == :minus_x) ? 0.0     : door_w

        pts = if along_y
                [
                  Geom::Point3d.new(-td, -door_w, 0), Geom::Point3d.new(0, -door_w, 0),
                  Geom::Point3d.new(0, 0, 0),         Geom::Point3d.new(-td, 0, 0)
                ]
              else
                [
                  Geom::Point3d.new(x0, 0, 0), Geom::Point3d.new(x1, 0, 0),
                  Geom::Point3d.new(x1, td, 0), Geom::Point3d.new(x0, td, 0)
                ]
              end
        face = definition.entities.add_face(pts)
        return nil unless face
        face.reverse! if face.normal.z < 0
        face.pushpull(door_h)

        if material
          definition.entities.grep(Sketchup::Face).each do |f|
            f.material      = material
            f.back_material = material
          end
        end

        if edge_config && mats && !edge_config.empty?
          PanelFactory.apply_edge_banding_by_config(definition, edge_config, mats)
        end

        open_angle = open_sign < 0 ? -max_angle.to_i : max_angle.to_i
        set_dc(definition, 'rotz', 0, access: 'TEXTBOX', label: 'زاوية الفتح (°)')

        %w[rotx roty lenx leny lenz _x _y _z _scale].each do |k|
          definition.set_attribute('dynamic_attributes', "#{k}_access", 'NONE')
        end

        definition.set_attribute('dynamic_attributes', 'onclick',
          "ANIMATE(\"rotz\", IF(rotz=0, #{open_angle}, 0), 10)")
        definition.set_attribute('dynamic_attributes', '_hasbehaviors', '1')
        definition.set_attribute('dynamic_attributes', 'name', definition.name)

        transform = Geom::Transformation.new(Geom::Point3d.new(hinge_x, hinge_y, hinge_z))
        instance = ents.add_instance(definition, transform)
        instance.name = name
        instance
      end

      def self.open_doors(instance = nil);  rotate_doors(90, instance); end
      def self.close_doors(instance = nil); rotate_doors(0,  instance); end
      def self.reset_doors(instance = nil); rotate_doors(0,  instance); end

      def self.rotate_doors(angle_deg, instance = nil)
        model = Sketchup.active_model
        instance ||= model.selection.first
        return puts('[Cabinet Neo] ⚠️  حدد وحدة أولاً') unless instance
        return puts('[Cabinet Neo] ⚠️  ليس مكوّناً') unless instance.is_a?(Sketchup::ComponentInstance)

        model.start_operation('تحريك الأبواب', true)
        begin
        count = 0
        instance.definition.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance)
          next unless ent.definition.get_attribute('CabinetNeo', 'is_door', false)

          dir = ent.definition.get_attribute('CabinetNeo', 'hinge_direction', 'plus_x')
          max_open = ent.definition.get_attribute('CabinetNeo', 'open_angle', DOOR_OPEN_ANGLE).to_f
          ang      = angle_deg.abs > 0.001 ? max_open : 0.0
          actual = (dir == 'minus_x') ? -ang : ang
          door_pos = ent.transformation.origin
          base = Geom::Transformation.new(door_pos)
          ent.transformation = if actual.abs > 0.001
            rot = Geom::Transformation.rotation(door_pos, Geom::Vector3d.new(0,0,1), actual.degrees)
            rot * base
          else
            base
          end
          ent.set_attribute('dynamic_attributes', 'rotz', actual.to_s)
          count += 1
        end
        instance.definition.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance)
          next unless ent.definition.get_attribute('CabinetNeo', 'is_flip', false)
          max_open = ent.definition.get_attribute('CabinetNeo', 'flip_open_angle', 90.0).to_f
          ang  = angle_deg.abs > 0.001 ? max_open : 0.0
          pos  = ent.transformation.origin
          base = Geom::Transformation.new(pos)
          ent.transformation = if ang > 0.001
            Geom::Transformation.rotation(pos, Geom::Vector3d.new(1, 0, 0), ang.degrees) * base
          else
            base
          end
          count += 1
        end
        dcount = 0
        instance.definition.entities.each do |ent|
          next unless ent.respond_to?(:get_attribute)
          next unless ent.get_attribute('CabinetNeo', 'drawer_slide', false)
          open_mm = ent.get_attribute('CabinetNeo', 'drawer_open_mm', DRAWER_OPEN_MM).to_f
          cur_mm  = ent.get_attribute('CabinetNeo', 'drawer_offset_mm', 0.0).to_f
          target  = angle_deg.abs > 0.001 ? open_mm : 0.0
          delta   = target - cur_mm
          next if delta.abs < 0.001
          ent.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, delta.mm, 0)) * ent.transformation
          ent.set_attribute('CabinetNeo', 'drawer_offset_mm', target)
          dcount += 1
        end
        model.commit_operation
        puts "[Cabinet Neo] 🗄️ حُرّكت #{dcount} قطعة أدراج" if dcount > 0
        puts "[Cabinet Neo] 🚪 حُرّكت #{count} درفة إلى #{angle_deg}°"
        rescue StandardError => e
          begin; model.abort_operation; rescue StandardError; end
          puts "[Cabinet Neo] ❌ rotate_doors: #{e.message}"
          puts e.backtrace.first(5).join("\n")
        end
      end

      def self.regenerate(instance = nil)
        model = Sketchup.active_model
        instance ||= model.selection.first
        return puts('[Cabinet Neo] ⚠️  حدد وحدة أولاً') unless instance
        return puts('[Cabinet Neo] ⚠️  ليس مكوّناً') unless instance.is_a?(Sketchup::ComponentInstance)

        dc = instance.definition.attribute_dictionary('dynamic_attributes', false)
        return puts('[Cabinet Neo] ⚠️  لا توجد DC attributes') unless dc

        w       = parse_len(dc['lenx'],   600.0)
        d       = parse_len(dc['leny'],   580.0)
        body_h  = parse_len(dc['body_h'], 780.0)
        swing   = dc['door_swing'].to_s
        shelves = dc['shelf_count'].to_i

        dbd_json = instance.definition.get_attribute('CabinetNeo', 'drawer_box_depths', nil)
        drawer_box_depths = begin
          dbd_json ? JSON.parse(dbd_json) : C::DRAWER_BOX_DEPTHS_DEFAULT
        rescue StandardError
          C::DRAWER_BOX_DEPTHS_DEFAULT
        end

        door_type = case swing
                    when 'right' then 'single_right'
                    when 'left'  then 'single_left'
                    else              'double'
                    end

        cat     = instance.definition.get_attribute('CabinetNeo', 'unit_category', 'lower')
        subtype = instance.definition.get_attribute('CabinetNeo', 'unit_subtype', nil)
        subtype = 'standard' if subtype.nil? || subtype.to_s.strip.empty?
        if instance.definition.get_attribute('CabinetNeo', 'cn_sink_unit', false)
          subtype = 'sink'
        end

        dh_json = instance.definition.get_attribute('CabinetNeo', 'drawer_heights', nil)
        drawer_heights = begin
          dh_json ? JSON.parse(dh_json) : C::DRAWER_HEIGHTS_DEFAULT
        rescue StandardError
          C::DRAWER_HEIGHTS_DEFAULT
        end

        xform = Geom::Transformation.new(instance.transformation.to_a)
        name  = instance.name

        puts "[Cabinet Neo] 🔄 إعادة بناء #{name} (subtype=#{subtype})"

        model.start_operation('إعادة بناء الخزانة', true)
        begin
          ovd = instance.definition.get_attribute('CabinetNeo', 'oven_drawer', 'none') || 'none'
          ovb_str = instance.definition.get_attribute('CabinetNeo', 'oven_drawer_box', 'true')
          ovb = (ovb_str.to_s == 'true')

          cwr = instance.definition.get_attribute('CabinetNeo', 'corner_w_right', nil)
          cwl = instance.definition.get_attribute('CabinetNeo', 'corner_w_left',  nil)
          cdr = instance.definition.get_attribute('CabinetNeo', 'corner_d_right', nil)
          cdl = instance.definition.get_attribute('CabinetNeo', 'corner_d_left',  nil)

          fside = instance.definition.get_attribute('CabinetNeo', 'fixed_side',    'left')
          cfw   = instance.definition.get_attribute('CabinetNeo', 'counter_width', 500.0)
          ffw   = instance.definition.get_attribute('CabinetNeo', 'filler_width',  150.0)

          tmd   = instance.definition.get_attribute('CabinetNeo', 'tall_micro_door_h',  450.0)
          tbh   = instance.definition.get_attribute('CabinetNeo', 'tall_bottom_h',      620.0)
          tbt   = instance.definition.get_attribute('CabinetNeo', 'tall_bottom_type',   'drawers')
          tnh   = instance.definition.get_attribute('CabinetNeo', 'tall_niche_h',       350.0)
          tonh  = instance.definition.get_attribute('CabinetNeo', 'tall_oven_niche_h',  600.0)
          ttdr  = instance.definition.get_attribute('CabinetNeo', 'tall_tray_drawer_h', 150.0)
          tsp   = instance.definition.get_attribute('CabinetNeo', 'ts_params', nil)

          old_def = instance.definition
          old_def.instances.to_a.each do |i|
            begin
              p = i.parent
              i.erase! if p && p.valid?
            rescue StandardError
            end
          end
          begin
            old_def.erase! if old_def.valid?
          rescue StandardError
          end

          new_inst = build({
            width: w.to_i, height: body_h.to_i, depth: d.to_i,
            door_type: door_type, shelves: shelves,
            unit_category: cat,
            unit_subtype: subtype,
            drawer_heights: drawer_heights,
            drawer_box_depths: drawer_box_depths,
            oven_drawer: ovd,
            oven_drawer_box: ovb,
            corner_w_right: cwr,
            corner_w_left:  cwl,
            corner_d_right: cdr,
            corner_d_left:  cdl,
            fixed_side:    fside,
            counter_width: cfw,
            filler_width:  ffw,
            tall_micro_door_h:  tmd,
            tall_bottom_h:      tbh,
            tall_bottom_type:   tbt,
            tall_niche_h:       tnh,
            tall_oven_niche_h:  tonh,
            tall_tray_drawer_h: ttdr,
            ts: tsp,
            skip_zoom: true, skip_purge: true, custom_name: name
          })
          new_inst.transformation = xform
          new_inst.name = name
          assign_unit_tag(new_inst, cat)

          model.commit_operation
          puts '[Cabinet Neo] ✅ تم إعادة البناء'
          new_inst
        rescue StandardError => e
          model.abort_operation
          puts "[Cabinet Neo] ❌ فشل: #{e.message}"
          raise e
        end
      end

      def self.validate!(params)
        w = params[:width].to_f; h = params[:height].to_f; d = params[:depth].to_f
        raise "العرض صغير جداً" if w < C::MIN_WIDTH
        raise "الارتفاع صغير جداً" if h < C::MIN_HEIGHT
        raise "العمق صغير جداً" if d < C::MIN_DEPTH
        raise 'العرض كبير جداً' if w > C::MAX_DIMENSION
        raise 'الارتفاع كبير جداً' if h > C::MAX_DIMENSION
        raise 'العمق كبير جداً' if d > C::MAX_DIMENSION
        valid = %w[single_left single_right double]
        raise "نوع باب غير معروف: #{params[:door_type]}" unless valid.include?(params[:door_type].to_s)

        valid_subtypes = %w[standard drawers oven corner_L sink counter_fixed tall_oven tall_storage]
        sub = (params[:unit_subtype] || 'standard').to_s
        sub = 'corner_L' if sub == 'corner'
        raise "نوع فرعي غير معروف: #{sub}" unless valid_subtypes.include?(sub)
      end
    end
  end
end