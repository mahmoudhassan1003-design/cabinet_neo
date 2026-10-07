# encoding: UTF-8
# =============================================================================
# أداة الحوض — v6 (إصلاح كامل)
# =============================================================================

module CabinetNeo
  module Tools
    class SinkTool
      DEFAULT_WIDTH         = 800.0
      DEFAULT_DEPTH         = 450.0
      DEFAULT_RIM           = 30.0
      DEFAULT_HEIGHT        = 180.0
      DEFAULT_RIM_THICKNESS = 3.0

      def initialize(opts = {})
        @sink_w = (opts[:width]  || DEFAULT_WIDTH).to_f
        @sink_d = (opts[:depth]  || DEFAULT_DEPTH).to_f
        @rim_w  = (opts[:rim]    || DEFAULT_RIM).to_f
        @sink_h = (opts[:height] || DEFAULT_HEIGHT).to_f
        @rim_t  = (opts[:rim_thickness] || DEFAULT_RIM_THICKNESS).to_f
        @shape  = (opts[:shape] || 'rectangle').to_s
        @color  = opts[:color] || '#bec3c8'
        @bowls  = (opts[:bowls] || 1).to_i
        @custom_model_name = opts[:custom_model] || nil
      end

      def activate
        @model = Sketchup.active_model
        @ip    = Sketchup::InputPoint.new
        @preview = nil
        @sink_def = nil
        Sketchup.status_text = "🖱️  اضغط لاختيار مكان الحوض | ESC للإلغاء"
        puts '[SinkTool] ✅ Activated'
        if @custom_model_name
          puts "[SinkTool] 🎯 Custom model: #{@custom_model_name}"
        end
      rescue StandardError => e
        puts "[SinkTool] activate error: #{e.message}"
      end

      def deactivate(view)
        cleanup_preview
        Sketchup.status_text = ''
        view.invalidate if view
      rescue StandardError
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        return unless @ip.valid?

        point = @ip.position
        countertop = find_countertop_at(point)
        return unless countertop

        top_z = countertop_surface_z(countertop)
        return unless top_z

        @hover_ct = countertop
        update_preview(point, top_z)
        view.invalidate
      rescue StandardError => e
        puts "[SinkTool] onMouseMove: #{e.message}"
      end

      def onLButtonDown(_flags, x, y, view)
        @ip.pick(view, x, y)
        return unless @ip.valid?

        point = @ip.position
        countertop = find_countertop_at(point)

        unless countertop
          ::UI.beep
          puts '[SinkTool] ⚠️  الرخامة غير موجودة تحت المؤشر'
          return
        end

        top_z = countertop_surface_z(countertop)
        unless top_z
          ::UI.beep
          return
        end

        place_sink(countertop, point, top_z)
        cleanup_preview
        @model.select_tool(nil)
      rescue StandardError => e
        puts "[SinkTool] onLButtonDown: #{e.message}"
        puts e.backtrace.first(8).join("\n")
        ::UI.beep
      end

      def onCancel(_reason, view)
        cleanup_preview
        @model.select_tool(nil)
        view.invalidate if view
      rescue StandardError
      end

      def draw(_view); end

      # -----------------------------------------------------------------------
      # public — عشان SinkPopup يقدر يستدعيها
      # -----------------------------------------------------------------------
      def get_or_create_sink_definition(model = nil)
        model = model || @model || Sketchup.active_model

        unless model
          puts "[SinkTool] ⚠️  لا يوجد model"
          return nil
        end

        # لو فيه موديل مخصص
        if @custom_model_name && !@custom_model_name.to_s.empty?
          existing = model.definitions[@custom_model_name]
          if existing
            @sink_def = existing
            return @sink_def
          else
            puts "[SinkTool] ⚠️  الموديل '#{@custom_model_name}' مش موجود — fallback للافتراضي"
          end
        end

        key = "#{@sink_w.to_i}x#{@sink_d.to_i}x#{@sink_h.to_i}_r#{@rim_w.to_i}_#{@shape}_#{@bowls}_#{@color.gsub('#','')}"
        def_name = "CabinetNeoSink_#{key}"

        existing = model.definitions[def_name]
        if existing
          @sink_def = existing
          return @sink_def
        end

        @sink_def = build_sink_definition(model, def_name)
        @sink_def
      end

      private

                  def find_countertop_at(point)
        # ابدأ من نقطة أعلى بـ 10 سم عشان الشعاع يخترق الوجه
        start_pt = Geom::Point3d.new(point.x, point.y, point.z + 100.mm)
        ray = [start_pt, Geom::Vector3d.new(0, 0, -1)]
        hit = @model.raytest(ray, false)
        return nil unless hit

        path = hit[1]
        path.each do |ent|
          # تحقق من الـ entity نفسه
          return ent if countertop_entity?(ent)

          # تحقق من الآباء (لو الـ entity داخل مجموعة)
          parent = ent.respond_to?(:parent) ? ent.parent : nil
          while parent
            return parent if countertop_entity?(parent)
            parent = parent.respond_to?(:parent) ? parent.parent : nil
          end
        end
        nil
      rescue StandardError => e
        puts "[SinkTool] find_countertop_at: #{e.message}"
        nil
      end

      def countertop_entity?(ent)
        return false unless ent.is_a?(Sketchup::Group) || ent.is_a?(Sketchup::ComponentInstance)
        ent.get_attribute('CabinetNeo', 'is_countertop', false) ? true : false
      rescue StandardError
        false
      end

      def countertop_surface_z(countertop)
        return nil unless countertop && countertop.valid?
        ct = Geometry::Constants::COUNTERTOP_THICKNESS.mm
        z0 = countertop.get_attribute('CabinetNeo', 'ct_z', nil)
        z0 ? z0.to_f + ct : countertop.bounds.min.z + ct
      rescue StandardError
        nil
      end

      def update_preview(point, top_z)
        unless @preview && @preview.valid?
          @preview = nil
          begin
            @preview = @model.entities.add_group
            @preview.set_attribute('CabinetNeo', 'is_sink_preview', true)
            defn = get_or_create_sink_definition
            return unless defn
            @preview.entities.add_instance(defn, Geom::Transformation.new)
          rescue StandardError => e
            puts "[SinkTool] preview create failed: #{e.message}"
            @preview = nil
            return
          end
        end

        begin
          @preview.transformation = sink_transform(point, top_z, @hover_ct)
        rescue StandardError => e
          puts "[SinkTool] preview transform failed: #{e.message}"
          @preview = nil
        end
      end

      def cleanup_preview
        return unless @preview
        begin
          @preview.erase! if @preview.valid?
        rescue StandardError
        end
        @preview = nil
      end

      def build_sink_definition(model, def_name)
        if @custom_model_name && !@custom_model_name.to_s.empty?
          existing = model.definitions[@custom_model_name]
          if existing
            puts "[SinkTool] ✅ استخدام موديل 3D Warehouse: #{@custom_model_name}"
            existing.set_attribute('CabinetNeo', 'is_sink', true)
            existing.set_attribute('CabinetNeo', 'custom_model', true)
            return existing
          end
        end

        defn = model.definitions.add(def_name)
        defn.set_attribute('CabinetNeo', 'generated', true)
        defn.set_attribute('CabinetNeo', 'is_sink', true)
        defn.set_attribute('CabinetNeo', 'sink_w', @sink_w)
        defn.set_attribute('CabinetNeo', 'sink_d', @sink_d)
        defn.set_attribute('CabinetNeo', 'sink_h', @sink_h)
        defn.set_attribute('CabinetNeo', 'rim_w',  @rim_w)
        defn.set_attribute('CabinetNeo', 'rim_t',  @rim_t)
        defn.set_attribute('CabinetNeo', 'shape',  @shape)
        defn.set_attribute('CabinetNeo', 'color',  @color)
        defn.set_attribute('CabinetNeo', 'bowls',  @bowls)

        ents = defn.entities

        case @shape
        when 'double'
          build_double_basin(ents)
        when 'round'
          build_round_basin(ents)
        else
          build_rect_basin(ents)
        end

        mat = get_or_create_material(model, @color)
        if mat
          ents.grep(Sketchup::Face).each do |f|
            f.material      = mat
            f.back_material = mat
          end
        end

        defn
      rescue StandardError => e
        puts "[SinkTool] build_sink_definition: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        defn
      end

      def build_rect_basin(ents)
        w  = @sink_w.mm
        d  = @sink_d.mm
        rw = @rim_w.mm
        rt = @rim_t.mm
        bh = @sink_h.mm

        o1 = Geom::Point3d.new(0.0, 0.0, 0.0)
        o2 = Geom::Point3d.new(w,   0.0, 0.0)
        o3 = Geom::Point3d.new(w,   d,   0.0)
        o4 = Geom::Point3d.new(0.0, d,   0.0)
        ot1 = Geom::Point3d.new(0.0, 0.0, rt)
        ot2 = Geom::Point3d.new(w,   0.0, rt)
        ot3 = Geom::Point3d.new(w,   d,   rt)
        ot4 = Geom::Point3d.new(0.0, d,   rt)
        i1 = Geom::Point3d.new(rw,     rw,     rt)
        i2 = Geom::Point3d.new(w - rw, rw,     rt)
        i3 = Geom::Point3d.new(w - rw, d - rw, rt)
        i4 = Geom::Point3d.new(rw,     d - rw, rt)
        b1 = Geom::Point3d.new(rw,     rw,     -bh)
        b2 = Geom::Point3d.new(w - rw, rw,     -bh)
        b3 = Geom::Point3d.new(w - rw, d - rw, -bh)
        b4 = Geom::Point3d.new(rw,     d - rw, -bh)

        safe_face(ents, [o1, o2, ot2, ot1])
        safe_face(ents, [o2, o3, ot3, ot2])
        safe_face(ents, [o3, o4, ot4, ot3])
        safe_face(ents, [o4, o1, ot1, ot4])
        safe_face(ents, [ot1, ot2, i2, i1])
        safe_face(ents, [ot2, ot3, i3, i2])
        safe_face(ents, [ot3, ot4, i4, i3])
        safe_face(ents, [ot4, ot1, i1, i4])
        safe_face(ents, [i1, i2, b2, b1])
        safe_face(ents, [i2, i3, b3, b2])
        safe_face(ents, [i3, i4, b4, b3])
        safe_face(ents, [i4, i1, b1, b4])
        safe_face(ents, [b1, b2, b3, b4])
      end

      def build_double_basin(ents)
        w  = @sink_w.mm
        d  = @sink_d.mm
        rw = @rim_w.mm
        rt = @rim_t.mm
        bh = @sink_h.mm
        div = 20.0.mm

        o1 = Geom::Point3d.new(0.0, 0.0, 0.0)
        o2 = Geom::Point3d.new(w,   0.0, 0.0)
        o3 = Geom::Point3d.new(w,   d,   0.0)
        o4 = Geom::Point3d.new(0.0, d,   0.0)
        ot1 = Geom::Point3d.new(0.0, 0.0, rt)
        ot2 = Geom::Point3d.new(w,   0.0, rt)
        ot3 = Geom::Point3d.new(w,   d,   rt)
        ot4 = Geom::Point3d.new(0.0, d,   rt)

        safe_face(ents, [o1, o2, ot2, ot1])
        safe_face(ents, [o2, o3, ot3, ot2])
        safe_face(ents, [o3, o4, ot4, ot3])
        safe_face(ents, [o4, o1, ot1, ot4])

        half = w / 2.0
        cx0 = half - div / 2.0
        cx1 = half + div / 2.0

        li1 = Geom::Point3d.new(rw,     rw,     rt)
        li2 = Geom::Point3d.new(cx0,    rw,     rt)
        li3 = Geom::Point3d.new(cx0,    d - rw, rt)
        li4 = Geom::Point3d.new(rw,     d - rw, rt)
        lb1 = Geom::Point3d.new(rw,     rw,     -bh)
        lb2 = Geom::Point3d.new(cx0,    rw,     -bh)
        lb3 = Geom::Point3d.new(cx0,    d - rw, -bh)
        lb4 = Geom::Point3d.new(rw,     d - rw, -bh)

        ri1 = Geom::Point3d.new(cx1,    rw,     rt)
        ri2 = Geom::Point3d.new(w - rw, rw,     rt)
        ri3 = Geom::Point3d.new(w - rw, d - rw, rt)
        ri4 = Geom::Point3d.new(cx1,    d - rw, rt)
        rb1 = Geom::Point3d.new(cx1,    rw,     -bh)
        rb2 = Geom::Point3d.new(w - rw, rw,     -bh)
        rb3 = Geom::Point3d.new(w - rw, d - rw, -bh)
        rb4 = Geom::Point3d.new(cx1,    d - rw, -bh)

        safe_face(ents, [li1, li2, lb2, lb1])
        safe_face(ents, [li2, li3, lb3, lb2])
        safe_face(ents, [li3, li4, lb4, lb3])
        safe_face(ents, [li4, li1, lb1, lb4])
        safe_face(ents, [lb1, lb2, lb3, lb4])

        safe_face(ents, [ri1, ri2, rb2, rb1])
        safe_face(ents, [ri2, ri3, rb3, rb2])
        safe_face(ents, [ri3, ri4, rb4, rb3])
        safe_face(ents, [ri4, ri1, rb1, rb4])
        safe_face(ents, [rb1, rb2, rb3, rb4])
      end

      def build_round_basin(ents)
        r  = [@sink_w, @sink_d].min / 2.0
        rw = @rim_w.mm
        rt = @rim_t.mm
        bh = @sink_h.mm
        cx = r
        cy = r
        seg = 32

        outer_top = []
        outer_bot = []
        inner_top = []
        basin_bot = []

        (0...seg).each do |i|
          ang = 2 * Math::PI * i / seg
          c = Math.cos(ang); s = Math.sin(ang)
          outer_top << Geom::Point3d.new(cx + r * c,        cy + r * s,        rt)
          outer_bot << Geom::Point3d.new(cx + r * c,        cy + r * s,        0.0)
          inner_top << Geom::Point3d.new(cx + (r - rw) * c, cy + (r - rw) * s, rt)
          basin_bot << Geom::Point3d.new(cx + (r - rw) * c, cy + (r - rw) * s, -bh)
        end

        (0...seg).each do |i|
          j = (i + 1) % seg
          safe_face(ents, [outer_bot[i], outer_bot[j], outer_top[j], outer_top[i]])
        end
        (0...seg).each do |i|
          j = (i + 1) % seg
          safe_face(ents, [outer_top[i], outer_top[j], inner_top[j], inner_top[i]])
        end
        (0...seg).each do |i|
          j = (i + 1) % seg
          safe_face(ents, [inner_top[i], inner_top[j], basin_bot[j], basin_bot[i]])
        end
        safe_face(ents, basin_bot)
      end

      def safe_face(ents, pts)
        begin
          ents.add_face(pts)
        rescue StandardError
          nil
        end
      end

      def get_or_create_material(model, hex)
        hex = hex.to_s.sub('#', '')
        name = "ستانلس_#{hex}"

        existing = model.materials[name]
        return existing if existing

        mat = model.materials.add(name)
        r = hex[0..1].to_i(16)
        g = hex[2..3].to_i(16)
        b = hex[4..5].to_i(16)
        mat.color = Sketchup::Color.new(r, g, b)

        ladb = mat.attribute_dictionary('ladb_opencutlist', true)
        ladb['type'] = 5

        mat
      rescue StandardError
        nil
      end

      def place_sink(countertop, point, top_z)
        @model.start_operation('إضافة حوض', true)
        begin
          cut_hole_in_countertop(countertop, point, top_z)

          sink_def = get_or_create_sink_definition
          return unless sink_def

          transform = sink_transform(point, top_z, countertop)
          sink_inst = @model.entities.add_instance(sink_def, transform)
          sink_inst.name = 'حوض'

          @model.commit_operation
          @model.active_view.invalidate
          puts "[SinkTool] ✅ تم وضع الحوض"
        rescue StandardError => e
          @model.abort_operation
          raise e
        end
      end

      def cut_hole_in_countertop(countertop, point, top_z)
        xa, ya = axes_for(countertop)
        self.class.cut_hole(countertop, Geom::Point3d.new(point.x, point.y, top_z),
                            @sink_w, @sink_d, @rim_w, xa, ya)
      end

      # اتجاه الحوض = اتجاه الرخامة (العمق على محور الوش v)
      def axes_for(countertop)
        vx = countertop ? countertop.get_attribute('CabinetNeo', 'axis_v_x', 0.0).to_f : 0.0
        vy = countertop ? countertop.get_attribute('CabinetNeo', 'axis_v_y', 1.0).to_f : 1.0
        [[vy, -vx], [vx, vy]]       # [x-axis (u), y-axis (v)]
      end

      def sink_transform(point, top_z, countertop)
        xa, ya = axes_for(countertop)
        ang = Math.atan2(ya[1], ya[0]) - Math::PI / 2.0
        center = Geom::Point3d.new(point.x, point.y, top_z)
        Geom::Transformation.new(center) *
          Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Geom::Vector3d.new(0, 0, 1), ang) *
          Geom::Transformation.translation(Geom::Vector3d.new(-(@sink_w / 2.0).mm, -(@sink_d / 2.0).mm, 0))
      end

      public

      # قص فتحة الحوض في قطعة رخام — بيشتغل مع الرخامة المتلفّة
      # center: Point3d بالعالم على سطح الرخامة | w,d,rim بالمم | xa,ya = [x,y] محاور الحوض
      def self.cut_hole(countertop, center, w_mm, d_mm, rim_mm, xa, ya)
        ents      = countertop.entities
        thickness = Geometry::Constants::COUNTERTOP_THICKNESS.mm
        half_w    = (w_mm - 2 * rim_mm).mm / 2.0
        half_d    = (d_mm - 2 * rim_mm).mm / 2.0
        return if half_w <= 0 || half_d <= 0

        inv = countertop.transformation.inverse
        corners_w = [[-1, -1], [1, -1], [1, 1], [-1, 1]].map do |sx, sy|
          Geom::Point3d.new(
            center.x + xa[0] * half_w * sx + ya[0] * half_d * sy,
            center.y + xa[1] * half_w * sx + ya[1] * half_d * sy,
            center.z
          )
        end
        pts = corners_w.map { |p| inv * p }
        z_top = pts.first.z

        face = ents.add_face(pts)
        return unless face
        face.reverse! if face.normal.z < 0
        face.pushpull(-thickness)

        z_bottom = z_top - thickness
        lc = inv * center
        target = nil
        ents.grep(Sketchup::Face).each do |f|
          next unless f.normal.z.abs > 0.9
          next unless (f.bounds.center.z - z_bottom).abs < 1.mm
          next unless f.bounds.contains?(Geom::Point3d.new(lc.x, lc.y, z_bottom))
          next unless f.bounds.width  < 2 * half_w + 2 * half_d + 10.mm
          next unless f.bounds.height < 2 * half_w + 2 * half_d + 10.mm
          next unless f.edges.all? { |e| e.faces.size < 2 || e.faces.all? { |ff| ff.normal.z.abs < 0.9 || ff == f } }
          target = f
          break
        end
        target.erase! if target && target.valid?
      rescue StandardError => e
        puts "[SinkTool] cut_hole: #{e.message}"
      end
    end
  end
end

puts '[Cabinet Neo] ✅ sink_tool.rb loaded'