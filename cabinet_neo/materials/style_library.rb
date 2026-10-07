# encoding: UTF-8
# =============================================================================
# مكتبة الأنماط — v8 (تجاهل وحدات الحوض)
# =============================================================================

require 'json'
require 'securerandom'

module CabinetNeo
  module Materials
    module StyleLibrary

      def self.styles_file_path
        File.expand_path(File.join(__dir__, '..', 'user_styles.json'))
      end

      def self.textures_dir
        File.expand_path(File.join(__dir__, '..', 'textures'))
      end

      # =======================================================================
      # الأنماط الجاهزة
      # =======================================================================
      def self.presets
        [
          {
            id: 'modern_white', name: 'Modern White', name_ar: 'أبيض عصري',
            desc: 'أبيض سادة للدرف والعلب',
            colors: ['#f0f0eb', '#fafaf8', '#d5d8dd'],
            surface: {
              carcass: { material: 'كونتر' },
              door:    { solid: '#fafaf8', name: 'UV LAC أبيض 18' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { material: 'كونتر' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط ابيض مط1', back: 'مفحار1', left: 'شريط ابيض مط1', right: 'شريط ابيض مط1' },
              side:       { front: 'شريط ابيض مط1', back: 'مفحار1', top: 'شريط ابيض مط1' },
              shelf:      { front: 'شريط ابيض مط1' },
              front_rail: { front: 'شريط ابيض مط1', back: 'شريط ابيض مط1' },
              back_rail:  { top: 'شريط ابيض مط1' },
              door:       { left: 'شريط سادة', right: 'شريط سادة', top: 'شريط سادة', bottom: 'شريط سادة' }
            }
          },
          {
            id: 'wood_classic', name: 'Wood Classic', name_ar: 'كلاسيك خشب',
            desc: 'خشب LUMBER + علب كونتر',
            colors: ['#c2d8ff', '#b8b2ad', '#8d939c'],
            surface: {
              carcass: { material: 'كونتر' },
              door:    { material: 'LUMBER J-Y114' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { material: 'كونتر' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط ابيض مط1', back: 'مفحار1', left: 'شريط ابيض مط1', right: 'شريط ابيض مط1' },
              side:       { front: 'شريط ابيض مط1', back: 'مفحار1', top: 'شريط ابيض مط1' },
              shelf:      { front: 'شريط ابيض مط1' },
              front_rail: { front: 'شريط ابيض مط1', back: 'شريط ابيض مط1' },
              back_rail:  { top: 'شريط ابيض مط1' },
              door:       { left: 'شريط خشبي', right: 'شريط خشبي', top: 'شريط خشبي', bottom: 'شريط خشبي' }
            }
          },
          {
            id: 'hpl_maple', name: 'HPL Maple', name_ar: 'HPL قيقب',
            desc: 'خشب قيقب فاتح بصورة',
            colors: ['#c2d8ff', '#e8c99b', '#c2a173'],
            surface: {
              carcass: { material: 'كونتر' },
              door:    { texture: 'hpl_maple', name: 'HPL Maple' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { material: 'كونتر' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط ابيض مط1', back: 'مفحار1', left: 'شريط ابيض مط1', right: 'شريط ابيض مط1' },
              side:       { front: 'شريط ابيض مط1', back: 'مفحار1', top: 'شريط ابيض مط1' },
              shelf:      { front: 'شريط ابيض مط1' },
              front_rail: { front: 'شريط ابيض مط1', back: 'شريط ابيض مط1' },
              back_rail:  { top: 'شريط ابيض مط1' },
              door:       { left: 'شريط خشبي', right: 'شريط خشبي', top: 'شريط خشبي', bottom: 'شريط خشبي' }
            }
          },
          {
            id: 'hpl_oak', name: 'HPL Oak', name_ar: 'HPL بلوط',
            desc: 'خشب بلوط طبيعي بصورة',
            colors: ['#c2d8ff', '#d4b58c', '#a88659'],
            surface: {
              carcass: { material: 'كونتر' },
              door:    { texture: 'hpl_oak', name: 'HPL Oak' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { material: 'كونتر' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط ابيض مط1', back: 'مفحار1', left: 'شريط ابيض مط1', right: 'شريط ابيض مط1' },
              side:       { front: 'شريط ابيض مط1', back: 'مفحار1', top: 'شريط ابيض مط1' },
              shelf:      { front: 'شريط ابيض مط1' },
              front_rail: { front: 'شريط ابيض مط1', back: 'شريط ابيض مط1' },
              back_rail:  { top: 'شريط ابيض مط1' },
              door:       { left: 'شريط خشبي', right: 'شريط خشبي', top: 'شريط خشبي', bottom: 'شريط خشبي' }
            }
          },
          {
            id: 'hpl_walnut', name: 'HPL Walnut', name_ar: 'HPL جوز',
            desc: 'خشب جوز داكن فاخر',
            colors: ['#c2d8ff', '#8b6b52', '#5a4433'],
            surface: {
              carcass: { material: 'كونتر' },
              door:    { texture: 'hpl_walnut', name: 'HPL Walnut' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { material: 'كونتر' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط ابيض مط1', back: 'مفحار1', left: 'شريط ابيض مط1', right: 'شريط ابيض مط1' },
              side:       { front: 'شريط ابيض مط1', back: 'مفحار1', top: 'شريط ابيض مط1' },
              shelf:      { front: 'شريط ابيض مط1' },
              front_rail: { front: 'شريط ابيض مط1', back: 'شريط ابيض مط1' },
              back_rail:  { top: 'شريط ابيض مط1' },
              door:       { left: 'شريط خشبي', right: 'شريط خشبي', top: 'شريط خشبي', bottom: 'شريط خشبي' }
            }
          },
          {
            id: 'matte_grey', name: 'Matte Grey', name_ar: 'رمادي مطفي',
            desc: 'رمادي سادة للدرف والعلب',
            colors: ['#5a6068', '#767c83', '#3a4048'],
            surface: {
              carcass: { solid: '#5a6068', name: 'كونتر رمادي' },
              door:    { solid: '#767c83', name: 'UV LAC رمادي 18' },
              back:    { material: 'ظهور بورديوم 6مملي' },
              shelf:   { solid: '#5a6068', name: 'كونتر رمادي' },
              plinth:  { material: 'اكسسوار' },
              handle:  { material: 'مقبض حرف L اسود' }
            },
            edges: {
              floor:      { front: 'شريط رمادي', back: 'مفحار1', left: 'شريط رمادي', right: 'شريط رمادي' },
              side:       { front: 'شريط رمادي', back: 'مفحار1', top: 'شريط رمادي' },
              shelf:      { front: 'شريط رمادي' },
              front_rail: { front: 'شريط رمادي', back: 'شريط رمادي' },
              back_rail:  { top: 'شريط رمادي' },
              door:       { left: 'شريط رمادي', right: 'شريط رمادي', top: 'شريط رمادي', bottom: 'شريط رمادي' }
            }
          }
        ]
      end

      # =======================================================================
      # الأنماط المخصصة
      # =======================================================================
      def self.custom_styles
        path = styles_file_path
        return [] unless File.exist?(path)
        raw = File.read(path, encoding: 'UTF-8')
        return [] if raw.strip.empty?
        data = JSON.parse(raw)
        return [] unless data.is_a?(Array)
        data.map { |s| symbolize_keys(s) }
      rescue StandardError => e
        puts "[Cabinet Neo] custom_styles: #{e.message}"
        []
      end

      def self.all
        presets + custom_styles
      end

      def self.find(style_id)
        all.find { |s| s[:id].to_s == style_id.to_s }
      end

      def self.save_custom_style(style_data)
        styles = custom_styles
        existing = styles.find { |s| s[:id] == style_data[:id] }
        if existing
          styles.map! { |s| s[:id] == style_data[:id] ? style_data : s }
        else
          styles << style_data
        end

        File.write(styles_file_path, JSON.pretty_generate(styles), encoding: 'UTF-8')
        { success: true, count: styles.size }
      rescue StandardError => e
        { success: false, reason: e.message }
      end

      def self.delete_custom_style(style_id)
        styles = custom_styles
        original = styles.size
        styles.reject! { |s| s[:id] == style_id }
        return { success: false, reason: 'النمط غير موجود' } if styles.size == original

        File.write(styles_file_path, JSON.pretty_generate(styles), encoding: 'UTF-8')
        { success: true, count: styles.size }
      rescue StandardError => e
        { success: false, reason: e.message }
      end

      # =======================================================================
      # التطبيق
      # =======================================================================
      def self.apply(model, style_id)
        unit = model.selection.first
        unless unit.is_a?(Sketchup::ComponentInstance)
          return { success: false, reason: 'حدد وحدة أولاً' }
        end

        unless unit.definition.get_attribute('CabinetNeo', 'generated', false)
          return { success: false, reason: 'العنصر المحدد ليس وحدة Cabinet Neo' }
        end

        # ⭐ v8: تجاهل وحدات الحوض — لها خامة بورديوم مخصصة
                subtype = unit.definition.get_attribute('CabinetNeo', 'unit_subtype', 'standard').to_s
        is_sink = unit.definition.get_attribute('CabinetNeo', 'cn_sink_unit', false)
        if subtype == 'sink' || is_sink
          puts '[StyleLibrary] ⏭️  تخطي وحدة الحوض — لها خامة بورديوم مخصصة'
          return { success: false, reason: 'وحدة الحوض لها خامة بورديوم مخصصة ولا تُطبق عليها الأنماط' }
        end

        style = find(style_id)
        return { success: false, reason: 'النمط غير موجود' } unless style

        puts '=' * 60
        puts "[StyleLibrary] تطبيق: #{style[:name_ar]}"
        puts '=' * 60

        model.start_operation('تطبيق النمط', true)
        begin
          count = 0

          unit.definition.entities.each do |ent|
            next unless ent.is_a?(Sketchup::ComponentInstance)
            next unless ent.definition.get_attribute('CabinetNeo', 'generated', false)

            # ⭐ v8: تخطي أبواب الحوض
            next if ent.definition.get_attribute('CabinetNeo', 'is_sink_door', false)

            piece_key = classify_piece(ent)
            next unless piece_key

            surface_key = surface_key_for(piece_key)
            next unless surface_key

            spec = style[:surface][surface_key]

            mat = spec ? resolve_surface_material(model, spec) : nil
            unless mat
              puts "  ⚠️  #{ent.name}: لم تُحلّ المادة السطحية (#{spec.inspect}) — سيتم تطبيق الحاشية فقط"
            end

            if mat
              ent.definition.entities.grep(Sketchup::Face).each do |f|
                bb = f.bounds
                dims = [
                  bb.width.to_mm.round(1),
                  bb.depth.to_mm.round(1),
                  bb.height.to_mm.round(1)
                ].sort
                next if (dims[1] - 18.0).abs < 3.0
                f.material      = mat
                f.back_material = mat
              end
            end

            edge_config = style[:edges][piece_key]
            if edge_config && !edge_config.empty?
              apply_edges_to_piece(ent, edge_config, model)
            else
              clear_edges(ent)
            end

            mat_name = mat ? mat.name : '—'
            puts "  ✅ #{ent.name.ljust(28)} → #{piece_key.to_s.ljust(12)} → #{mat_name}"
            count += 1
          end

          unit.definition.set_attribute('CabinetNeo', 'style_id', style_id.to_s)

          model.commit_operation
          model.active_view.invalidate

          puts '-' * 60
          puts "  🎨 إجمالي: #{count} قطعة"
          puts '=' * 60

          { success: true, count: count, style: style[:name_ar] || style[:name] }
        rescue StandardError => e
          model.abort_operation
          puts "[StyleLibrary] ❌ فشل: #{e.message}"
          puts e.backtrace.first(10).join("\n")
          { success: false, reason: e.message }
        end
      end

      # =======================================================================
      # ⭐ تبديل الخامة: سادة ↔ خشب (داخلي + خارجي) — بضغطة واحدة من الشريط العائم
      # =======================================================================
      WOOD_EDGE  = 'شريط خشبي'.freeze
      PLAIN_EDGE = 'شريط ابيض مط1'.freeze

      def self.plain_all_style
        e = PLAIN_EDGE
        {
          name: 'Plain', name_ar: 'سادة',
          surface: {
            carcass: { material: 'كونتر' },
            door:    { solid: '#fafaf8', name: 'UV LAC أبيض 18' },
            back:    { material: 'ظهور بورديوم 6مملي' },
            shelf:   { material: 'كونتر' },
            plinth:  { material: 'اكسسوار' },
            handle:  { material: 'مقبض حرف L اسود' }
          },
          edges: {
            floor:      { front: e, back: 'مفحار1', left: e, right: e },
            side:       { front: e, back: 'مفحار1', top: e },
            shelf:      { front: e },
            front_rail: { front: e, back: e },
            back_rail:  { top: e },
            door:       { left: 'شريط سادة', right: 'شريط سادة', top: 'شريط سادة', bottom: 'شريط سادة' }
          }
        }
      end

      def self.wood_all_style
        e = WOOD_EDGE
        oak = { texture: 'hpl_oak', name: 'HPL Oak' }
        {
          name: 'All Wood', name_ar: 'خشب كامل',
          surface: {
            carcass: oak, door: oak, shelf: oak,
            back:    { material: 'ظهور بورديوم 6مملي' },
            plinth:  { material: 'اكسسوار' },
            handle:  { material: 'مقبض حرف L اسود' }
          },
          edges: {
            floor:      { front: e, back: 'مفحار1', left: e, right: e },
            side:       { front: e, back: 'مفحار1', top: e },
            shelf:      { front: e },
            front_rail: { front: e, back: e },
            back_rail:  { top: e },
            door:       { left: e, right: e, top: e, bottom: e }
          }
        }
      end

      def self.sink_unit?(unit)
        unit.definition.get_attribute('CabinetNeo', 'unit_subtype', 'standard').to_s == 'sink' ||
          unit.definition.get_attribute('CabinetNeo', 'cn_sink_unit', false)
      end

      # 'plain' أو 'wood'
      def self.current_surface_mode(unit)
        m = unit.definition.get_attribute('CabinetNeo', 'surface_mode', nil)
        return m.to_s if m
        sid = unit.definition.get_attribute('CabinetNeo', 'style_id', '').to_s
        (sid =~ /wood|hpl_/) ? 'wood' : 'plain'
      end

      # بيطبّق نمط على وحدة واحدة من غير ما يفتح Operation (المنادي مسؤول)
      def self.apply_style_hash_to_unit(model, unit, style)
        count = 0
        unit.definition.entities.each do |ent|
          next unless ent.is_a?(Sketchup::ComponentInstance)
          next unless ent.definition.get_attribute('CabinetNeo', 'generated', false)
          next if ent.definition.get_attribute('CabinetNeo', 'is_sink_door', false)

          piece_key = classify_piece(ent)
          next unless piece_key
          surface_key = surface_key_for(piece_key)
          next unless surface_key

          spec = style[:surface][surface_key]
          mat  = spec ? resolve_surface_material(model, spec) : nil
          # لو صورة الخشب مش موجودة نستخدم خامة الخشب الافتراضية
          mat ||= model.materials[Geometry::Constants::MAT_DOOR_WOOD] if spec && spec[:texture]

          if mat
            ent.definition.entities.grep(Sketchup::Face).each do |f|
              bb = f.bounds
              dims = [bb.width.to_mm.round(1), bb.depth.to_mm.round(1), bb.height.to_mm.round(1)].sort
              next if (dims[1] - 18.0).abs < 3.0
              f.material      = mat
              f.back_material = mat
            end
          end

          edge_config = style[:edges][piece_key]
          if edge_config && !edge_config.empty?
            apply_edges_to_piece(ent, edge_config, model)
          else
            clear_edges(ent)
          end
          count += 1
        end
        count
      end

      # =======================================================================
      # أوشاش الوحدة بس (درف + واجهات أدراج — بما فيها الدواليب)
      # من غير العلب الداخلية (جنب/أرضية/أرفف/ضهر/صناديق الأدراج/المقابض)
      # =======================================================================
      FRONT_NAME_RE = /درفة|واجهة درج/

      def self.front_piece?(ent)
        return false unless ent.is_a?(Sketchup::ComponentInstance)
        return false unless ent.definition.get_attribute('CabinetNeo', 'generated', false)
        return false if ent.definition.get_attribute('CabinetNeo', 'is_sink_door', false)
        name = ent.definition.get_attribute('CabinetNeo', 'piece_name', nil).to_s
        name = ent.name.to_s if name.empty?
        name =~ FRONT_NAME_RE ? true : false
      end

      def self.apply_fronts_to_unit(model, unit, style)
        spec = style[:surface][:door]
        edge_config = style[:edges][:door]
        count = 0
        walk = lambda do |ents|
          ents.each do |ent|
            case ent
            when Sketchup::ComponentInstance
              if front_piece?(ent)
                paint_front_piece(model, ent, spec, edge_config)
                count += 1
              else
                walk.call(ent.definition.entities)
              end
            when Sketchup::Group
              walk.call(ent.entities)
            end
          end
        end
        walk.call(unit.definition.entities)
        count
      end

      def self.paint_front_piece(model, ent, spec, edge_config)
        mat = spec ? resolve_surface_material(model, spec) : nil
        mat ||= model.materials[Geometry::Constants::MAT_DOOR_WOOD] if spec && spec[:texture]
        if mat
          ent.definition.entities.grep(Sketchup::Face).each do |f|
            bb = f.bounds
            dims = [bb.width.to_mm.round(1), bb.depth.to_mm.round(1), bb.height.to_mm.round(1)].sort
            next if (dims[1] - 18.0).abs < 3.0
            f.material      = mat
            f.back_material = mat
          end
        end
        if edge_config && !edge_config.empty?
          apply_edges_to_piece(ent, edge_config, model)
        else
          clear_edges(ent)
        end
      end

      def self.toggle_plain_wood(model, units)
        units = Array(units).select do |u|
          u.is_a?(Sketchup::ComponentInstance) && u.valid? &&
            u.definition.get_attribute('CabinetNeo', 'generated', false)
        end
        skipped = units.count { |u| sink_unit?(u) }
        units = units.reject { |u| sink_unit?(u) }
        if units.empty?
          return { success: false, reason: skipped > 0 ? 'وحدة الحوض لها خامة بورديوم مخصصة' : 'حدد وحدة (أو أكتر) من وحدات Cabinet Neo الأول.' }
        end

        target = current_surface_mode(units.first) == 'wood' ? 'plain' : 'wood'
        style  = target == 'wood' ? wood_all_style : plain_all_style

        Materials::MaterialLibrary.prepare_defaults(model)

        model.start_operation(target == 'wood' ? 'تحويل إلى خشب' : 'تحويل إلى سادة', true)
        begin
          pieces = 0
          units.each do |u|
            pieces += apply_fronts_to_unit(model, u, style)   # الأوشاش بس — العلب الداخلية زي ما هي
            u.definition.set_attribute('CabinetNeo', 'surface_mode', target)
            u.definition.set_attribute('CabinetNeo', 'style_id', target == 'wood' ? 'wood_all' : 'plain_all')
          end
          model.commit_operation
          model.active_view.invalidate
          { success: true, mode: target, units: units.size, pieces: pieces }
        rescue StandardError => e
          model.abort_operation
          puts "[StyleLibrary] toggle_plain_wood: #{e.message}"
          puts e.backtrace.first(6).join("\n")
          { success: false, reason: e.message }
        end
      end

      def self.resolve_surface_material(model, spec)
        return nil if spec.nil?

        if spec[:texture]
          mat_name = spec[:name] || spec[:texture]
          return TextureLoader.ensure_texture_material(model, mat_name, spec[:texture])
        end
        if spec[:solid]
          mat_name = spec[:name] || "Solid_#{spec[:solid].gsub('#', '')}"
          return TextureLoader.ensure_solid_material(model, mat_name, spec[:solid])
        end
        if spec[:material]
          mat = model.materials[spec[:material]]
          return mat if mat
          return nil
        end
        nil
      end

      def self.current_style_id(unit)
        return nil unless unit.is_a?(Sketchup::ComponentInstance)
        unit.definition.get_attribute('CabinetNeo', 'style_id', nil)
      rescue StandardError
        nil
      end

      def self.classify_piece(piece)
        name = if piece.is_a?(Sketchup::ComponentInstance)
                 stored = piece.definition.get_attribute('CabinetNeo', 'piece_name', nil)
                 (stored && !stored.empty?) ? stored : piece.name.to_s
               else
                 piece.to_s
               end

        case name
        when /درفة/           then :door
        when /ضهرية/          then :back
        when /مقبض/           then :handle
        when /أرضية/          then :floor
        when /جنب/            then :side
        when /مداد أمامي/     then :front_rail
        when /مداد خلفي/      then :back_rail
        when /رف/             then :shelf
        when /وزر/            then :plinth
        else nil
        end
      end

      def self.surface_key_for(piece_key)
        case piece_key
        when :floor, :side, :shelf, :front_rail, :back_rail
          :carcass
        when :door    then :door
        when :back    then :back
        when :plinth  then :plinth
        when :handle  then :handle
        else nil
        end
      end

      def self.apply_edges_to_piece(piece, edge_config, model)
        clear_edges(piece)
        surface_mat = get_surface_material(piece)

        applied = 0
        piece.definition.entities.grep(Sketchup::Face).each do |face|
          bb = face.bounds
          dims = [
            bb.width.to_mm.round(1),
            bb.depth.to_mm.round(1),
            bb.height.to_mm.round(1)
          ].sort
          next unless (dims[1] - 18.0).abs < 3.0

          n = face.normal
          direction = case
                      when n.y > 0.9  then :front
                      when n.y < -0.9 then :back
                      when n.x > 0.9  then :right
                      when n.x < -0.9 then :left
                      when n.z > 0.9  then :top
                      when n.z < -0.9 then :bottom
                      else nil
                      end
          next unless direction

          mat_name = edge_config[direction]
          next unless mat_name

          mat = ensure_edge_material(model, mat_name)
          mat ||= surface_mat
          next unless mat

          face.material      = mat
          face.back_material = mat
          applied += 1
        end

        puts "  🎨 #{piece.name}: #{applied} حاشية"
        applied
      rescue StandardError => e
        puts "[StyleLibrary] apply_edges_to_piece: #{e.message}"
        0
      end

      def self.ensure_edge_material(model, mat_name)
        return nil if mat_name.nil? || mat_name.to_s.strip.empty?

        existing = model.materials[mat_name]
        return existing if existing

        puts "  ➕ إنشاء مادة حاشية مفقودة: #{mat_name}"
        mat = model.materials.add(mat_name)
        mat.color = Sketchup::Color.new(200, 200, 200)

        ladb = mat.attribute_dictionary('ladb_opencutlist', true)
        ladb['type'] = 4
        ladb['uuid'] ||= SecureRandom.uuid
        ladb['std_widths']       ||= '18mm'
        ladb['std_thicknesses']  ||= '1mm'
        ladb['raw_estimated']    ||= true
        ladb['edge_decremented'] ||= false
        ladb['grained']          ||= false
        ladb['length_increase']  ||= '0'
        ladb['thickness_increase'] ||= '0'
        ladb['width_increase']   ||= '0'
        ladb['multiplier_coefficient'] ||= 1.0
        ladb['description']      ||= ''
        ladb['url']              ||= ''
        ladb['std_prices']       ||= '[{"val":"","dim":null}]'
        ladb['std_cut_prices']   ||= '[{"val":"","dim":null}]'
        ladb['std_volumic_masses'] ||= '[{"val":"","dim":null}]'
        ladb['std_lengths']      ||= ''
        ladb['std_sections']     ||= ''
        ladb['thickness']        ||= '0'

        legacy = mat.attribute_dictionary('OpenCutList', true)
        legacy['type'] = 'edge'

        mat
      rescue StandardError => e
        puts "[StyleLibrary] ensure_edge_material('#{mat_name}'): #{e.message}"
        nil
      end

      def self.get_surface_material(piece)
        piece.definition.entities.grep(Sketchup::Face).each do |f|
          bb = f.bounds
          dims = [
            bb.width.to_mm.round(1),
            bb.depth.to_mm.round(1),
            bb.height.to_mm.round(1)
          ].sort
          return f.material if (dims[1] - 18.0).abs >= 3.0 && f.material
        end
        nil
      end

      def self.clear_edges(piece)
        surface_mat = nil
        piece.definition.entities.grep(Sketchup::Face).each do |f|
          bb = f.bounds
          dims = [
            bb.width.to_mm.round(1),
            bb.depth.to_mm.round(1),
            bb.height.to_mm.round(1)
          ].sort
          if (dims[1] - 18.0).abs >= 3.0 && f.material
            surface_mat = f.material
            break
          end
        end

        piece.definition.entities.grep(Sketchup::Face).each do |f|
          bb = f.bounds
          dims = [
            bb.width.to_mm.round(1),
            bb.depth.to_mm.round(1),
            bb.height.to_mm.round(1)
          ].sort
          if (dims[1] - 18.0).abs < 3.0 && surface_mat
            f.material      = surface_mat
            f.back_material = surface_mat
          end
        end
      end

      def self.symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)
        hash.each_with_object({}) do |(k, v), h|
          new_val = v.is_a?(Hash) ? symbolize_keys(v) : v
          h[k.to_s.to_sym] = new_val
        end
      end

      def self.style_for_ui(style, current_id)
        texture_url = nil

        (style[:surface] || {}).each do |_key, spec|
          next unless spec.is_a?(Hash) && spec[:texture]
          found = find_texture_filename(spec[:texture])
          next unless found

          abs_path = File.expand_path(found).gsub('\\', '/')
          abs_path = "/#{abs_path}" unless abs_path.start_with?('/')
          texture_url = "file://#{abs_path}"
          break
        end

        {
          id:          style[:id],
          name:        style[:name],
          name_ar:     style[:name_ar],
          desc:        style[:desc],
          colors:      style[:colors] || ['#cccccc', '#aaaaaa', '#888888'],
          texture_url: texture_url,
          is_current:  (style[:id].to_s == current_id.to_s)
        }
      end

      def self.find_texture_filename(base_name)
        return nil unless File.directory?(textures_dir)
        %w[.jpg .jpeg .png .bmp].each do |ext|
          candidate = File.join(textures_dir, "#{base_name}#{ext}")
          return candidate if File.exist?(candidate)
        end
        nil
      end

      def self.to_json_list(model = nil)
        current = nil
        if model
          unit = model.selection.first
          current = current_style_id(unit) if unit
        end

        {
          current: current,
          presets: presets.map { |s| style_for_ui(s, current) },
          custom:  custom_styles.map { |s| style_for_ui(s, current) }
        }
      end

      def self.available_materials_for_ui(model)
        return { boards: [], edges: [], hardware: [] } unless model

        boards   = []
        edges    = []
        hardware = []

        model.materials.each do |mat|
          ocl = mat.attribute_dictionary('ladb_opencutlist', false)
          next unless ocl
          type = ocl['type'].to_i

          color = if mat.color
                    format('#%02x%02x%02x',
                           mat.color.red, mat.color.green, mat.color.blue)
                  else
                    '#cccccc'
                  end

          entry = { name: mat.name, color: color, has_texture: !mat.texture.nil? }

          case type
          when 2 then boards << entry
          when 4 then edges << entry
          when 5 then hardware << entry
          end
        end

        {
          boards:   boards.sort_by { |h| h[:name] },
          edges:    edges.sort_by  { |h| h[:name] },
          hardware: hardware.sort_by { |h| h[:name] }
        }
      end
    end
  end
end