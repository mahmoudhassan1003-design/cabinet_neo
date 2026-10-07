# encoding: UTF-8
# =============================================================================
# باني الرخامة — v2
# =============================================================================
# - بيركّب الرخامة فوق الوحدات السفلية (Base) بس.
#     × دواليب الفرن / التخزين الطويلة بتتستبعد
#     × الوحدات العلوية بتتستبعد
# - بيشتغل على شكل الوحدة الحقيقي من فوق (بيدعم الوحدات المتلفّة)
# - الوحدات المتجاورة على نفس الخط بتتجمّع في قطعة واحدة متصلة
# - الكورنر L: ذراعين = قطعتين رخام منفصلتين (كل ذراع على حيطتها)
# - السماكة 4 سم / بروز أمامي 4 سم / مراية 6 سم × 2 سم من ورا
# - بعد إعادة البناء بيرجّع قصّات الأحواض الموجودة تلقائي
# =============================================================================

module CabinetNeo
  module Geometry
    module CountertopBuilder
      C  = Constants
      FP = UnitFootprint

      GROUP_NAME     = 'رخامة المطبخ'.freeze
      MAX_BASE_BODY_H_MM = 1000.0   # أي وحدة أطول من كده مش وحدة سفلية

      # ---------------------------------------------------------------------
      # الواجهة الرئيسية
      # ---------------------------------------------------------------------
      def self.build_for_lower_units
        model = Sketchup.active_model
        return { success: false, reason: 'لا يوجد موديل مفتوح' } unless model

        units = find_lower_units(model)
        return { success: false, reason: 'لا توجد وحدات سفلية في المشهد' } if units.empty?

        rects = units.flat_map { |u| unit_rects(u) }
        return { success: false, reason: 'فشل حساب أبعاد الوحدات' } if rects.empty?

        pieces = merge_into_pieces(rects)
        return { success: false, reason: 'لا توجد أسطح صالحة للرخامة' } if pieces.empty?

        mats = Materials::MaterialLibrary.prepare_defaults(model)

        model.start_operation('إنشاء الرخامة', true)
        begin
          sinks = collect_sinks(model)
          remove_existing_countertop(model)

          groups = pieces.each_with_index.map do |pc, i|
            create_piece(model, pc, mats, i + 1, pieces.size)
          end

          recut_sinks(groups, sinks)

          model.commit_operation
          model.active_view.invalidate

          main = pieces.max_by { |p| p[:s1] - p[:s0] }
          {
            success: true,
            count:   units.size,
            pieces:  pieces.size,
            width:   (main[:s1] - main[:s0]).to_mm.round(1),
            depth:   (main[:f] - main[:b] + C::COUNTERTOP_OVERHANG.mm).to_mm.round(1),
            height:  C::COUNTERTOP_THICKNESS.to_mm.round(1)
          }
        rescue StandardError => e
          model.abort_operation
          puts "[CountertopBuilder] ❌ #{e.message}"
          puts e.backtrace.first(8).join("\n")
          { success: false, reason: e.message }
        end
      end

      # ---------------------------------------------------------------------
      # إيجاد الوحدات السفلية (Base فقط)
      # ---------------------------------------------------------------------
      def self.find_lower_units(model)
        model.entities.select { |ent| base_unit?(ent) }
      end

      def self.base_unit?(ent)
        return false unless FP.cabinet_unit?(ent) || legacy_unit?(ent)
        return false unless FP.category(ent) == 'lower'
        return false if FP::TALL_SUBTYPES.include?(FP.subtype(ent))
        return false if FP.body_height_mm(ent) > MAX_BASE_BODY_H_MM
        true
      rescue StandardError
        false
      end

      # وحدات قديمة اتعملت قبل ما نضيف unit_number
      def self.legacy_unit?(ent)
        ent.is_a?(Sketchup::ComponentInstance) && ent.valid? &&
          ent.definition.get_attribute('CabinetNeo', 'generated', false) &&
          !ent.definition.get_attribute('CabinetNeo', 'is_sink', false) &&
          ent.definition.name.to_s =~ /^وحدة/
      rescue StandardError
        false
      end

      # ---------------------------------------------------------------------
      # مستطيلات الوحدة في العالم
      #   v = اتجاه الوش (من الضهر للوش)    u = (v.y, -v.x)
      #   b = مسافة الضهر على v   f = مسافة الوش   s0..s1 = المدى على u
      # ---------------------------------------------------------------------
      def self.unit_rects(unit)
        oh = C::COUNTERTOP_OVERHANG.mm
        tr = unit.transformation
        z  = FP.top_z(unit)
        FP.local_rects(unit, oh).map { |r| make_rect(tr, r, z) }
      end

      def self.make_rect(tr, r, z)
        corners = [[r[:x0], r[:y0]], [r[:x1], r[:y0]], [r[:x1], r[:y1]], [r[:x0], r[:y1]]].map do |x, y|
          tr * Geom::Point3d.new(x, y, 0)
        end
        fv  = tr * Geom::Vector3d.new(r[:front][0], r[:front][1], 0)
        len = Math.sqrt(fv.x * fv.x + fv.y * fv.y)
        v = [fv.x / len, fv.y / len]
        u = [v[1], -v[0]]

        dv = corners.map { |p| p.x * v[0] + p.y * v[1] }
        du = corners.map { |p| p.x * u[0] + p.y * u[1] }

        wall_s = nil
        if r[:wall]
          wp = tr * Geom::Point3d.new(r[:wall][0], r[:wall][1], 0)
          wall_s = wp.x * u[0] + wp.y * u[1]
        end

        { v: v, u: u, b: dv.min, f: dv.max, s0: du.min, s1: du.max,
          z: z, walls: wall_s ? [wall_s] : [] }
      end

      # ---------------------------------------------------------------------
      # دمج المستطيلات المتجاورة على نفس الخط في قطع
      # ---------------------------------------------------------------------
      def self.merge_into_pieces(rects)
        line_tol = 3.mm
        gap_tol  = 5.mm
        z_tol    = 1.mm

        groups = []
        rects.each do |r|
          g = groups.find do |gg|
            ref = gg[:ref]
            (ref[:v][0] * r[:v][0] + ref[:v][1] * r[:v][1]) > 0.99995 &&
              (ref[:b] - r[:b]).abs < line_tol &&
              (ref[:z] - r[:z]).abs < z_tol
          end
          if g
            g[:rects] << r
          else
            groups << { ref: r, rects: [r] }
          end
        end

        pieces = []
        groups.each do |g|
          cur = nil
          g[:rects].sort_by { |r| r[:s0] }.each do |r|
            if cur && r[:s0] <= cur[:s1] + gap_tol
              cur[:s1]    = [cur[:s1], r[:s1]].max
              cur[:f]     = [cur[:f], r[:f]].max
              cur[:walls] += r[:walls]
            else
              pieces << cur if cur
              cur = r.merge(walls: r[:walls].dup)
            end
          end
          pieces << cur if cur
        end
        pieces.select { |p| (p[:s1] - p[:s0]) > 50.mm }
      end

      # ---------------------------------------------------------------------
      # إنشاء قطعة رخام (مع المراية)
      # ---------------------------------------------------------------------
      def self.create_piece(model, pc, mats, index, total)
        ct = C::COUNTERTOP_THICKNESS.mm
        oh = C::COUNTERTOP_OVERHANG.mm
        uh = C::UPSTAND_HEIGHT.mm
        ut = C::UPSTAND_THICKNESS.mm

        u = pc[:u]; v = pc[:v]
        s0 = pc[:s0]; s1 = pc[:s1]
        b  = pc[:b]
        tf = pc[:f] + oh            # حافة الوش بعد البروز
        z0 = pc[:z]

        pt = lambda do |s, t, z|
          Geom::Point3d.new(u[0] * s + v[0] * t, u[1] * s + v[1] * t, z)
        end

        group = model.entities.add_group
        group.name = total > 1 ? "#{GROUP_NAME} #{index}" : GROUP_NAME
        group.set_attribute('CabinetNeo', 'generated', true)
        group.set_attribute('CabinetNeo', 'is_countertop', true)
        group.set_attribute('CabinetNeo', 'piece_index', index)
        group.set_attribute('CabinetNeo', 'axis_u_x', u[0])
        group.set_attribute('CabinetNeo', 'axis_u_y', u[1])
        group.set_attribute('CabinetNeo', 'axis_v_x', v[0])
        group.set_attribute('CabinetNeo', 'axis_v_y', v[1])
        group.set_attribute('CabinetNeo', 'ct_s0', s0.to_f)
        group.set_attribute('CabinetNeo', 'ct_s1', s1.to_f)
        group.set_attribute('CabinetNeo', 'ct_b',  b.to_f)
        group.set_attribute('CabinetNeo', 'ct_f',  tf.to_f)
        group.set_attribute('CabinetNeo', 'ct_z',  z0.to_f)

        ents = group.entities

        # ---- الرخامة ----
        slab = ents.add_face(pt.call(s0, b, z0), pt.call(s1, b, z0),
                             pt.call(s1, tf, z0), pt.call(s0, tf, z0))
        slab.reverse! if slab.normal.z < 0
        slab.pushpull(ct)

        # ---- المراية: على الضهر + على جنب الحيط (لو الوحدة ركن) ----
        wall_tol = 8.mm
        wall0 = pc[:walls].any? { |w| (w - s0).abs < wall_tol }
        wall1 = pc[:walls].any? { |w| (w - s1).abs < wall_tol }
        zu = z0 + ct

        pts = []
        pts << pt.call(s0, b, zu)
        pts << pt.call(s1, b, zu)
        if wall1
          pts << pt.call(s1, tf, zu) << pt.call(s1 - ut, tf, zu) << pt.call(s1 - ut, b + ut, zu)
        else
          pts << pt.call(s1, b + ut, zu)
        end
        if wall0
          pts << pt.call(s0 + ut, b + ut, zu) << pt.call(s0 + ut, tf, zu) << pt.call(s0, tf, zu)
        else
          pts << pt.call(s0, b + ut, zu)
        end

        up = ents.add_face(pts)
        if up
          up.reverse! if up.normal.z < 0
          up.pushpull(uh)
        end

        if mats[:countertop]
          ents.grep(Sketchup::Face).each do |f|
            f.material      = mats[:countertop]
            f.back_material = mats[:countertop]
          end
        end

        puts "[CountertopBuilder] ✅ #{group.name}: #{(s1 - s0).to_mm.round(0)}×#{(tf - b).to_mm.round(0)} مم"
        group
      end

      # ---------------------------------------------------------------------
      # الأحواض الموجودة: نحفظها قبل الحذف ونرجّع قصّاتها بعد البناء
      # ---------------------------------------------------------------------
      def self.collect_sinks(model)
        model.entities.select do |e|
          e.is_a?(Sketchup::ComponentInstance) && e.valid? &&
            e.definition.get_attribute('CabinetNeo', 'is_sink', false)
        end
      end

      def self.recut_sinks(groups, sinks)
        return if sinks.empty? || groups.empty?
        return unless defined?(::CabinetNeo::Tools::SinkTool)

        sinks.each do |sk|
          next unless sk.valid?
          d  = sk.definition
          sw = d.get_attribute('CabinetNeo', 'sink_w', nil)
          sd = d.get_attribute('CabinetNeo', 'sink_d', nil)
          next unless sw && sd
          rim = d.get_attribute('CabinetNeo', 'rim_w', 30.0).to_f

          center = sk.transformation * Geom::Point3d.new((sw.to_f / 2.0).mm, (sd.to_f / 2.0).mm, 0)
          xa = sk.transformation.xaxis
          ya = sk.transformation.yaxis

          target = groups.find { |g| ct_contains?(g, center) }
          next unless target

          ::CabinetNeo::Tools::SinkTool.cut_hole(
            target, center, sw.to_f, sd.to_f, rim,
            [xa.x, xa.y], [ya.x, ya.y]
          )
        end
      rescue StandardError => e
        puts "[CountertopBuilder] recut_sinks: #{e.message}"
      end

      def self.ct_contains?(group, pt)
        ga = lambda { |k, dflt| group.get_attribute('CabinetNeo', k, dflt).to_f }
        u = [ga.call('axis_u_x', 1.0), ga.call('axis_u_y', 0.0)]
        v = [ga.call('axis_v_x', 0.0), ga.call('axis_v_y', 1.0)]
        s = pt.x * u[0] + pt.y * u[1]
        t = pt.x * v[0] + pt.y * v[1]
        s.between?(ga.call('ct_s0', 0.0) - 1.mm, ga.call('ct_s1', 0.0) + 1.mm) &&
          t.between?(ga.call('ct_b', 0.0) - 1.mm, ga.call('ct_f', 0.0) + 1.mm)
      end

      # ---------------------------------------------------------------------
      # حذف الرخامة الموجودة
      # ---------------------------------------------------------------------
      def self.remove_existing_countertop(model)
        to_remove = []
        model.entities.each do |ent|
          if ent.is_a?(Sketchup::Group) &&
             ent.get_attribute('CabinetNeo', 'is_countertop', false)
            to_remove << ent
          end
        end
        to_remove.each do |g|
          begin
            g.erase! if g.valid?
          rescue StandardError
          end
        end
        puts "[CountertopBuilder] 🧹 حذف #{to_remove.size} رخامة قديمة" if to_remove.size > 0
      end
    end
  end
end
