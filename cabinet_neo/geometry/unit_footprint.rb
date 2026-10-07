# encoding: UTF-8
# =============================================================================
# بصمة الوحدة (Footprint) — v1
# =============================================================================
# بيحسب شكل الوحدة من فوق (في الإحداثيات المحلية للوحدة) من غير ما يعتمد على
# الـ bounds الحقيقية (اللي بتتأثر بالأبواب المفتوحة والمقابض).
#
#   - وحدة عادية  : مستطيل  x:[0,عرض]  y:[0,عمق]   (الضهر عند y=0 والوش عند +Y)
#   - كورنر L     : ذراعين
#         ذراع 1 : x:[0,w1] y:[0,d1]    الوش ناحية +Y   (الحيط عند x=0)
#         ذراع 2 : x:[0,d2] y:[0,w2]    الوش ناحية +X
#
# يستخدمها: باني الرخامة + أداة المحاذاة واللف
# =============================================================================

module CabinetNeo
  module Geometry
    module UnitFootprint
      C = Constants

      TALL_SUBTYPES = %w[tall_oven tall_storage].freeze

      # ---- قراءة خصائص الوحدة ----------------------------------------------
      def self.dc(unit)
        unit.definition.attribute_dictionary('dynamic_attributes', false) || {}
      end

      def self.attr(unit, key, default = nil)
        unit.definition.get_attribute('CabinetNeo', key, default)
      end

      def self.subtype(unit)
        attr(unit, 'unit_subtype', 'standard').to_s
      end

      def self.category(unit)
        attr(unit, 'unit_category', 'lower').to_s
      end

      def self.cabinet_unit?(ent)
        ent.is_a?(Sketchup::ComponentInstance) && ent.valid? &&
          ent.definition.get_attribute('CabinetNeo', 'generated', false) &&
          !ent.definition.get_attribute('CabinetNeo', 'is_sink', false) &&
          !ent.definition.get_attribute('CabinetNeo', 'unit_number', nil).nil?
      rescue StandardError
        false
      end

      # بالمم
      def self.dims_mm(unit)
        d = dc(unit)
        [(d['lenx'] || C::DEFAULT_WIDTH).to_f,
         (d['leny'] || C::DEFAULT_DEPTH).to_f,
         (d['body_h'] || C::DEFAULT_HEIGHT).to_f]
      end

      def self.body_height_mm(unit)
        dims_mm(unit)[2]
      end

      # [w1, d1, w2, d2] بالمم  (نفس ترتيب build_corner_L)
      def self.corner_dims_mm(unit)
        w1 = attr(unit, 'corner_w_left',  C::CORNER_W_LEFT_DEFAULT).to_f
        w2 = attr(unit, 'corner_w_right', C::CORNER_W_RIGHT_DEFAULT).to_f
        d1 = attr(unit, 'corner_d_left',  C::CORNER_D_LEFT_DEFAULT).to_f
        d2 = attr(unit, 'corner_d_right', C::CORNER_D_RIGHT_DEFAULT).to_f
        [w1, d1, w2, d2]
      end

      # أعلى نقطة في الجسم (بدون الرخامة) في إحداثيات العالم
      def self.top_z(unit)
        z_local = (C::PLINTH_HEIGHT + body_height_mm(unit)).mm
        (unit.transformation * Geom::Point3d.new(0, 0, z_local)).z
      end

      # ---- المستطيلات المحلية ------------------------------------------------
      # arm2_trim: بنقص من أول الذراع التانية (للرخامة، عشان القطعتين مايتداخلوش)
      # بترجّع Array من Hash:
      #   x0,y0,x1,y1 (Length) / front: [fx,fy] / wall: [x,y] أو nil / role
      def self.local_rects(unit, arm2_trim = 0.0)
        if subtype(unit) == 'corner_L'
          w1, d1, w2, d2 = corner_dims_mm(unit).map(&:mm)
          rects = [
            { x0: 0.0, y0: 0.0, x1: w1, y1: d1, front: [0.0, 1.0],
              wall: [0.0, d1 / 2.0], role: :arm1 }
          ]
          y_start = d1 + arm2_trim
          if w2 - y_start > 1.mm
            rects << { x0: 0.0, y0: y_start, x1: d2, y1: w2, front: [1.0, 0.0],
                       wall: nil, role: :arm2 }
          end
          rects
        else
          w, d, _h = dims_mm(unit).map(&:mm)
          [{ x0: 0.0, y0: 0.0, x1: w, y1: d, front: [0.0, 1.0], wall: nil, role: :main }]
        end
      end

      # الحدود المحلية الكاملة [x0,y0,x1,y1]
      def self.local_bounds(unit)
        rs = local_rects(unit, 0.0)
        [rs.map { |r| r[:x0] }.min, rs.map { |r| r[:y0] }.min,
         rs.map { |r| r[:x1] }.max, rs.map { |r| r[:y1] }.max]
      end

      # أركان البصمة (حدود كاملة) في العالم — Array من Point3d عند z=0 للوحدة
      def self.world_corners(unit)
        x0, y0, x1, y1 = local_bounds(unit)
        tr = unit.transformation
        [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| tr * Geom::Point3d.new(x, y, 0) }
      end

      def self.world_center(unit)
        pts = world_corners(unit)
        xs = pts.map(&:x); ys = pts.map(&:y)
        Geom::Point3d.new((xs.min + xs.max) / 2.0, (ys.min + ys.max) / 2.0, 0)
      end

      # ---------------------------------------------------------------------
      # الهندسة الفعلية (مش الأبعاد الاسمية)
      # ---------------------------------------------------------------------
      # بنحسب أقصى امتداد حقيقي لجسم الوحدة في إحداثياتها المحلية من رؤوس الهندسة.
      # بنستبعد الأبواب والأدراج والمقابض (لأنها بتتحرك/بتبرز لما تتفتح) —
      # فالضهر والجنبين والأرضية بتتحسب بدقة، وده اللي بيمنع دخول الوحدة في الحيط.
      MOVABLE_RE = /درفة|درج|مقبض|واجهة/

      def self.movable_piece?(ent)
        name = ent.definition.get_attribute('CabinetNeo', 'piece_name', nil).to_s
        name = ent.name.to_s if name.empty?
        name =~ MOVABLE_RE ? true : false
      rescue StandardError
        false
      end

      # [x0, y0, x1, y1, z0, z1] بإحداثيات الوحدة المحلية — أو nil لو مفيش هندسة
      def self.real_local_bounds(unit)
        defn = unit.definition
        @rb_cache ||= {}
        b = defn.bounds
        sig = [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z].map { |v| v.to_f.round(5) }
        c = @rb_cache[defn.entityID]
        return c[:val] if c && c[:sig] == sig

        mn = [Float::INFINITY] * 3
        mx = [-Float::INFINITY] * 3
        take = lambda do |p|
          mn[0] = p.x if p.x < mn[0]; mx[0] = p.x if p.x > mx[0]
          mn[1] = p.y if p.y < mn[1]; mx[1] = p.y if p.y > mx[1]
          mn[2] = p.z if p.z < mn[2]; mx[2] = p.z if p.z > mx[2]
        end
        walk = lambda do |ents, tr, top|
          ents.each do |e|
            case e
            when Sketchup::Edge
              e.vertices.each { |v| take.call(tr * v.position) }
            when Sketchup::Group
              next if top && movable_piece?(e)
              walk.call(e.entities, tr * e.transformation, false)
            when Sketchup::ComponentInstance
              next if top && movable_piece?(e)
              walk.call(e.definition.entities, tr * e.transformation, false)
            end
          end
        end
        walk.call(defn.entities, Geom::Transformation.new, true)

        val = mn[0].infinite? ? nil : [mn[0], mn[1], mx[0], mx[1], mn[2], mx[2]]
        @rb_cache[defn.entityID] = { sig: sig, val: val }
        val
      rescue StandardError => e
        puts "[UnitFootprint] real_local_bounds: #{e.message}"
        nil
      end

      # أركان البصمة الفعلية (xy) في العالم — لو مفيش هندسة بترجع للأبعاد الاسمية
      def self.real_world_corners(unit)
        rb = real_local_bounds(unit)
        return world_corners(unit) unless rb
        x0, y0, x1, y1 = rb
        tr = unit.transformation
        [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| tr * Geom::Point3d.new(x, y, 0) }
      end

      # الاتجاه (heading) بالراديان: زاوية محور X المحلي على مستوى XY
      def self.heading(unit)
        xa = unit.transformation.xaxis
        Math.atan2(xa.y, xa.x)
      end

      # اتجاه الوش في العالم (متجه وحدة XY)
      def self.front_dir(unit)
        v = unit.transformation * Geom::Vector3d.new(0, 1, 0)
        len = Math.sqrt(v.x * v.x + v.y * v.y)
        len < 1e-9 ? [0.0, 1.0] : [v.x / len, v.y / len]
      end
    end
  end
end
