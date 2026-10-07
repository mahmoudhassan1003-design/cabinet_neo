# encoding: UTF-8
# =============================================================================
# جسر OpenCutList 7.x — يقرأ من ladb_opencutlist
# =============================================================================

module CabinetNeo
  module Materials
    module OCLBridge
      # أنواع OCL 7.x (integer)
      TYPE_BOARD    = 2
      TYPE_EDGE     = 4
      TYPE_BAR      = 3
      TYPE_HARDWARE = 6

      class << self

        # -------------------------------------------------------------------
        # قراءة المواد حسب النوع
        # -------------------------------------------------------------------
        def materials_by_type(model, type_int)
          return [] unless model
          model.materials.select do |mat|
            dict = mat.attribute_dictionary('ladb_opencutlist', false)
            next false unless dict
            dict['type'].to_i == type_int
          end
        rescue StandardError
          []
        end

        def panels(model);   materials_by_type(model, TYPE_BOARD);    end
        def edges(model);    materials_by_type(model, TYPE_EDGE);     end
        def bars(model);     materials_by_type(model, TYPE_BAR);      end
        def hardware(model); materials_by_type(model, TYPE_HARDWARE); end

        def available?
          return true if defined?(OpenCutList)
          SketchUp.extensions.any? { |e| e.name.to_s =~ /OpenCutList/i }
        rescue StandardError
          false
        end

        # -------------------------------------------------------------------
        # إرسال القوائم للواجهة
        # -------------------------------------------------------------------
        def to_json_list(model)
          {
            available: available?,
            panels:    mat_list(model, TYPE_BOARD),
            edges:     mat_list(model, TYPE_EDGE),
            bars:      mat_list(model, TYPE_BAR),
            hardware:  mat_list(model, TYPE_HARDWARE)
          }
        end

        def mat_list(model, type_int)
          materials_by_type(model, type_int).map do |m|
            ladb = m.attribute_dictionary('ladb_opencutlist', false) || {}
            {
              name:      m.name,
              color:     color_to_hex(m.color),
              type:      type_int,
              thickness: ladb['std_thickness'].to_s,
              width:     ladb['std_width'].to_s,
              length:    ladb['std_length'].to_s
            }
          end
        end

        def color_to_hex(color)
          return '#888888' unless color
          format('#%02x%02x%02x', color.red, color.green, color.blue)
        rescue StandardError
          '#888888'
        end

        # -------------------------------------------------------------------
        # تطبيق مادة على جزء من الوحدة
        # -------------------------------------------------------------------
        def apply_material(model, mat_name, part_type)
          mat = model.materials[mat_name]
          return { ok: false, reason: "الخامة غير موجودة: #{mat_name}" } unless mat

          instance = model.selection.first
          unless instance.is_a?(Sketchup::ComponentInstance)
            return { ok: false, reason: 'يجب تحديد وحدة أولاً' }
          end

          unless instance.definition.get_attribute('CabinetNeo', 'generated', false)
            return { ok: false, reason: 'العنصر المحدد ليس وحدة Cabinet Neo' }
          end

          model.start_operation('تطبيق مادة OCL', true)
          begin
            count = apply_to_parts(instance, mat, part_type)
            model.commit_operation
            { ok: true, count: count }
          rescue StandardError => e
            model.abort_operation
            { ok: false, reason: e.message }
          end
        end

        def apply_to_parts(instance, material, part_type)
          count = 0
          instance.definition.entities.each do |ent|
            next unless ent.is_a?(Sketchup::ComponentInstance) || ent.is_a?(Sketchup::Group)
            piece_name = get_piece_name(ent)
            next unless matches_type?(piece_name, part_type)
            paint_entity(ent, material)
            count += 1
          end
          count
        end

        def get_piece_name(ent)
          n = ent.respond_to?(:name) && !ent.name.empty? ? ent.name : ent.definition.name
          n.to_s
        end

        def matches_type?(name, part_type)
          case part_type.to_s
          when 'door'    then name =~ /درفة/
          when 'shelf'   then name =~ /رف/
          when 'back'    then name =~ /ضهرية/
          when 'carcass' then name =~ /جنب|أرضية|مداد|وزر/
          when 'handle'  then name =~ /مقبض/
          when 'all'     then true
          else false
          end
        end

        def paint_entity(entity, material)
          entity.material = material
          entity.entities.grep(Sketchup::Face).each do |f|
            f.material      = material
            f.back_material = material
          end
        end

        # -------------------------------------------------------------------
        # تشخيص
        # -------------------------------------------------------------------
        def debug_dump(model = nil)
          model ||= Sketchup.active_model
          return puts('[OCL] No model') unless model

          puts '=' * 70
          puts '[OCL] Materials with ladb_opencutlist:'
          model.materials.each do |m|
            dict = m.attribute_dictionary('ladb_opencutlist', false)
            next unless dict
            t = dict['type'].to_i
            tag = case t
                  when TYPE_BOARD    then 'لوح'
                  when TYPE_EDGE     then 'حاشية'
                  when TYPE_BAR      then 'قضيب'
                  when TYPE_HARDWARE then 'عتاد'
                  else "غير معروف (#{t})"
                  end
            puts "  #{m.name.ljust(30)} type=#{t} (#{tag}) thk=#{dict['std_thickness'].inspect}"
          end
          puts '=' * 70
        end
      end
    end
  end
end