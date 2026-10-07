# encoding: UTF-8
# =============================================================================
# أداة النقل — v2 (مراعاة الأرض + Shift لخط مستقيم)
# =============================================================================
# بتمسك الوحدة من ركنها العلوي الخلفي (شمال أو يمين) وتنقلها لأي نقطة بتختارها.
#   - الركن بيتحدد كأنك واقف قدام الوحدة وبتبص عليها (الوش ناحيتك).
#   - بتسنّب على نقط وحواف الموديل (InputPoint) — فتقدر تعلّق الركن في ركن الحيط.
#   - 🧱 الأرض: الوحدات الأرضية بتفضل واقفة على الأرض (حتى لو سنّبت على نقطة
#     عالية أو واطية). الوحدات العلوية (upper) حرة في الارتفاع.
#   - ⇧ Shift: اضغط واكتم → الحركة تتقفل على خط مستقيم (على محور الوحدة:
#     طول الحيط أو عمودي عليه). سيب Shift عشان تفك القفل.
#   - لو محدد أكتر من وحدة: كلهم بيتنقلوا مع بعض، والمسك من أول وحدة.
#
#   Click : تثبيت        Ctrl (مع الماوس) : تبديل الركن        Esc : إلغاء
#   ⌨️ اكتب رقم (مسافة) واضغط Enter → الوحدة تنزل بالمسافة دي في اتجاه حركة الماوس
#      (شغال من الـ VCB بتاع سكتش أب، ومن الشريط العائم لو الفوكس عليه)
#   وحدة واحدة: الضهر دايماً على الحيط + مغناطيس للوحدات اللي جنبها من غير فراغ
#      + لو قربت من حيط (60 سم) الوحدة بتلف لوحدها وضهرها ناحية الحيط
#   القائمة العائمة بتختفي مؤقتاً أثناء النقل (عشان Shift/Ctrl يشتغلوا) وبترجع لما تخلص
# =============================================================================

module CabinetNeo
  module Tools
    class MoveTool
      FP = Geometry::UnitFootprint

      # لو لقيت الشمال واليمين معكوسين عندك، بدّل القيمة دي بس
      LEFT_IS_LOCAL_MAX_X = true

      SHIFT_KEY  = defined?(::CONSTRAIN_MODIFIER_KEY)  ? ::CONSTRAIN_MODIFIER_KEY  : 16
      SHIFT_MASK = defined?(::CONSTRAIN_MODIFIER_MASK) ? ::CONSTRAIN_MODIFIER_MASK : 1
      MIN_LOCK_DISTANCE_MM = 5.0
      Z_AXIS = Geom::Vector3d.new(0, 0, 1)
      AUTO_ROTATE_TO_WALL = true   # false = الوحدة ماتلفش لوحدها

      # الأداة النشطة (عشان الشريط العائم يبعتلها الأرقام اللي بتتكتب)
      class << self
        attr_accessor :active

        def handle_key(key)
          t = @active
          t.handle_key(key) if t
        rescue StandardError => e
          puts "[MoveTool] key: #{e.message}"
        end
      end

      def initialize(units, corner = :left)
        @units  = Array(units).select { |u| u.valid? }
        @corner = corner == :right ? :right : :left
        @base_corner = @corner
        @grab   = nil
        @target = nil
        @delta  = nil
        @shift  = false
        @lock   = nil
        @floor_faces = []
        @single = @units.size == 1
        @walls = nil
        @rects = nil
        @typed = ''
        @dir = nil
        @raw_delta = nil
        @fit_ang = 0.0
        @others = nil
        @rects_cache = {}
      end

      # ---------- دورة حياة الأداة ----------
      def activate
        @model  = Sketchup.active_model
        @ip     = Sketchup::InputPoint.new
        @grab   = compute_grab_point
        @target = nil
        @delta  = nil
        @shift  = false
        @lock   = nil
        @fit_ang = 0.0
        @ground = @units.first ? Geometry::FloorSnap.ground_unit?(@units.first) : false
        @floor_faces = @ground ? Geometry::FloorSnap.collect_floor_faces(@model) : []
        self.class.active = self
        @typed = ''
        prepare_fit
        update_status
        @model.active_view.invalidate
      end

      def deactivate(view)
        self.class.active = nil if self.class.active.equal?(self)
        begin
          Sketchup.vcb_value = ''
        rescue StandardError
          nil
        end
        view.invalidate
        # رجّع القائمة العائمة (اتخفت وقت النقل)
        if defined?(::CabinetNeo::UI::FloatingToolbar)
          ::CabinetNeo::UI::FloatingToolbar.resume_after_tool
        end
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onCancel(_reason, view)
        @model.select_tool(nil)
        view.invalidate
      end

      def onSetCursor
        false
      end

      # ---------- الإدخال ----------
      def onKeyDown(key, _repeat, _flags, view)
        if key == SHIFT_KEY
          @shift = true
          update_status
        end
        view.invalidate
        false
      end

      def onKeyUp(key, _repeat, _flags, view)
        if key == SHIFT_KEY
          @shift = false
          @lock  = nil
          update_status
          view.invalidate
        end
        false
      end

      # Ctrl/Shift مع الماوس بيبدّل الركن (من flags الماوس — من غير ما القائمة العائمة تاخد الفوكس)
      CORNER_FLIP_MASK = (defined?(::COPY_MODIFIER_MASK) ? ::COPY_MODIFIER_MASK : 2)

      def sync_corner(flags)
        want = (flags.to_i & CORNER_FLIP_MASK) != 0 ? other_corner(@base_corner) : @base_corner
        return if want == @corner
        @corner = want
        @grab   = compute_grab_point
        update_status
      end

      def other_corner(c)
        c == :left ? :right : :left
      end

      # ---------- الكتابة بالكيبورد (VCB) ----------
      def enableVCB?
        true
      end

      # Enter من الـ VCB بتاع سكتش أب
      def onUserText(text, view)
        len = parse_length(text)
        return unless len
        apply_typed_length(len, view)
      end

      # أرقام جاية من الشريط العائم (0-9 . , - Backspace Enter Escape)
      def handle_key(key)
        k = key.to_s
        case k
        when /\A[0-9]\z/ then @typed << k
        when '.', ',' then @typed << '.' unless @typed.include?('.')
        when '-' then @typed = @typed.start_with?('-') ? @typed[1..-1].to_s : "-#{@typed}"
        when 'Backspace' then @typed = @typed[0..-2].to_s
        when 'Escape'
          @model.select_tool(nil)
          return
        when 'Enter'
          len = parse_length(@typed)
          apply_typed_length(len, @model.active_view) if len
          return
        else
          return
        end
        preview_typed
      end

      def onMouseMove(flags, x, y, view)
        sync_corner(flags)
        return if !@typed.empty? && @dir   # بنكتب مسافة → الاتجاه متثبت
        # Shift أحياناً بتيجي من الـ flags بس
        shift_now = @shift || ((flags.to_i & SHIFT_MASK) != 0)
        @lock = nil unless shift_now
        @shift_active = shift_now
        @ip.pick(view, x, y)
        update_from_pointer(view, x, y)
        view.invalidate
      end

      def onLButtonDown(flags, x, y, view)
        sync_corner(flags)
        @shift_active = @shift || ((flags.to_i & SHIFT_MASK) != 0)
        @ip.pick(view, x, y)
        update_from_pointer(view, x, y) if @typed.empty? || !@dir
        return unless @delta
        commit_move(@delta, view, @single)
      end

      # ---------- الرسم ----------
      def draw(view)
        @ip.draw(view) if @ip && @ip.valid?
        return unless @grab && @delta

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(255, 140, 40)
        @units.each do |u|
          next unless u.valid?
          view.draw_lines(*box_edges(u, @delta, @fit_ang))
        end

        tip = moved_grab
        view.draw_points([tip], 10, 2, Sketchup::Color.new(255, 107, 26))
        unless @typed.empty?
          begin
            sc = view.screen_coords(tip)
            view.draw_text(Geom::Point3d.new(sc.x + 14, sc.y - 22, 0), @typed, size: 14, bold: true)
          rescue StandardError
            nil
          end
        end

        if @lock
          # خط الإرشاد على المحور المقفول
          a = @grab.offset(@lock, -20000.mm)
          b = @grab.offset(@lock,  20000.mm)
          view.line_width = 1
          view.line_stipple = '_'
          view.drawing_color = Sketchup::Color.new(90, 200, 255)
          view.draw_lines(a, b)
          view.line_stipple = ''
        else
          view.line_stipple = '-'
          view.line_width = 1
          view.drawing_color = Sketchup::Color.new(255, 180, 90)
          view.draw_lines(@grab, tip)
          view.line_stipple = ''
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @units.each { |u| bb.add(u.bounds) if u.valid? }
        if @delta
          @units.each do |u|
            next unless u.valid?
            box_corners(u, @delta, @fit_ang).each { |p| bb.add(p) }
          end
        end
        bb
      end

      private

      def update_status
        side = @corner == :left ? 'الشمال' : 'اليمين'
        shift = @shift ? ' | ⇧ مقفول على خط مستقيم' : ' | ⇧ Shift لخط مستقيم'
        ground = @ground ? ' | 🧱 على الأرض' : ''
        Sketchup.status_text = "🖱️ اضغط لتثبيت الوحدة من ركنها العلوي الخلفي #{side}#{shift}#{ground} | Ctrl = الركن التاني | الوحدة بتلف والضهر بيتلزق في الحيط لو قريب | Esc إلغاء"
      end

      # ---------- حساب الإزاحة ----------
      def update_from_pointer(view, x, y)
        raw = raw_target(view, x, y)
        unless raw && @grab
          @delta = nil
          @raw_delta = nil
          return
        end
        @target    = raw
        @raw_delta = effective_delta(raw - @grab)
        remember_direction(@raw_delta)
        @delta = fit_delta(@raw_delta, true)
        show_vcb(@raw_delta)
      end

      # ---------- ضهر على الحيط + مغناطيس (وحدة واحدة بس) ----------
      def prepare_fit
        return unless @single
        u = @units.first
        @walls = ::CabinetNeo::Geometry::UnitArranger.collect_wall_faces(@model)
        puts "[MoveTool] أوجه الحيطان اللي اتلاقت: #{@walls.size}"
        @others = @model.entities.select do |e|
          next false if e.equal?(u)
          (FP.cabinet_unit?(e) || Geometry::CountertopBuilder.legacy_unit?(e))
        end
        @rects_cache = {}
        @rects = rects_for(0.0)
      rescue StandardError => e
        puts "[MoveTool] prepare_fit: #{e.message}"
        @walls = nil
        @rects = nil
        @others = nil
      end

      # مستطيلات الجيران في محاور الوحدة بعد لفّة ang (بتتحسب مرة لكل زاوية)
      def rects_for(ang)
        return nil unless @others
        key = ang.round(4)
        @rects_cache[key] ||= ::CabinetNeo::Geometry::UnitArranger.neighbor_rects(
          @units.first, @others, FP.heading(@units.first) + ang
        )
      end

      # بيرجّع الإزاحة النهائية، وبيحط زاوية اللف في @fit_ang (نفس القيمة بتتستخدم في الرسم والتثبيت)
      def fit_delta(d, magnet)
        @fit_ang = 0.0
        return d unless @single && (@walls || @others)
        arr = ::CabinetNeo::Geometry::UnitArranger
        u   = @units.first
        ang = AUTO_ROTATE_TO_WALL ? arr.plan_back_rotation(u, d, @walls) : 0.0
        if ang.abs > 0.0005 && @grab
          # بعد اللف حوالين المركز الركن المحدد بيتحرك — نعوّض عشان يفضل على نقطة الماوس (ركن الحيط)
          rot = Geom::Transformation.rotation(FP.world_center(u), Z_AXIS, ang)
          gr  = rot * @grab
          d   = Geom::Vector3d.new(@grab.x + d.x - gr.x, @grab.y + d.y - gr.y, d.z)
        end
        fit = arr.plan_move_fit(u, d, @walls, rects_for(ang), magnet, ang)
        @fit_ang = ang
        if (ang - (@logged_ang || 0.0)).abs > 0.01
          @logged_ang = ang
          puts format('[MoveTool] لف الضهر ناحية الحيط: %.1f° (walls=%d)', ang.radians, @walls ? @walls.size : 0)
        end
        Geom::Vector3d.new(d.x + fit.x, d.y + fit.y, d.z)
      rescue StandardError => e
        puts "[MoveTool] fit: #{e.message}"
        @fit_ang = 0.0
        d
      end

      # ---------- الاتجاه + الكتابة ----------
      def remember_direction(v)
        h = @ground ? Geom::Vector3d.new(v.x, v.y, 0) : v
        return if h.length < 1.mm
        @dir = if @lock
                 scale_vec(@lock, h.dot(@lock) >= 0 ? 1.0 : -1.0)
               else
                 h.normalize
               end
      end

      def parse_length(text)
        t = text.to_s.strip.tr(',', '.')
        return nil if t.empty? || t == '-' || t == '.'
        t.to_l
      rescue StandardError
        nil
      end

      def show_vcb(v)
        Sketchup.vcb_label = 'المسافة'
        Sketchup.vcb_value = Sketchup.format_length(v.length)
      rescue StandardError
        nil
      end

      def typed_delta(len)
        return nil unless @dir
        v = scale_vec(@dir, len.to_f)
        v = Geom::Vector3d.new(v.x, v.y, ground_dz(v)) if @ground
        v
      end

      def preview_typed
        len = parse_length(@typed)
        Sketchup.status_text = "⌨️ المسافة: #{@typed.empty? ? '—' : @typed}  (Enter للتنفيذ — Backspace للمسح — Esc إلغاء)"
        begin
          Sketchup.vcb_label = 'المسافة'
          Sketchup.vcb_value = @typed
        rescue StandardError
          nil
        end
        if len && @dir
          @raw_delta = typed_delta(len)
          @delta = fit_delta(@raw_delta, false)
        elsif !@dir
          Sketchup.status_text = '⌨️ حرّك الماوس ناحية الاتجاه الأول وبعدين اكتب المسافة'
        end
        @model.active_view.invalidate
      end

      def apply_typed_length(len, view)
        unless @dir
          Sketchup.status_text = '⌨️ حرّك الماوس ناحية الاتجاه الأول وبعدين اكتب المسافة'
          return
        end
        v = typed_delta(len)
        return unless v

        # ⭐ v2: للنقل بالأرقام — لف تلقائي + منع اختراق بس، من غير لزق زيادة في الحيط
        arr = ::CabinetNeo::Geometry::UnitArranger
        u   = @units.first
        ang = AUTO_ROTATE_TO_WALL ? arr.plan_back_rotation(u, v, @walls) : 0.0

        # compensation للف (الركن المسكوك يفضل على المسافة المضبوطة)
        if ang.abs > 0.0005 && @grab
          rot = Geom::Transformation.rotation(FP.world_center(u), Z_AXIS, ang)
          gr  = rot * @grab
          v   = Geom::Vector3d.new(@grab.x + v.x - gr.x, @grab.y + v.y - gr.y, v.z)
        end

        @fit_ang = ang
        # snap_wall=false → منع اختراق بس، من غير لزق
        fix = arr.plan_move_fit(u, v, @walls, nil, false, ang, false)
        v   = Geom::Vector3d.new(v.x + fix.x, v.y + fix.y, v.z)

        commit_move(v, view, @single)
      end

      # النقطة المستهدفة: من السنّاب لو فيه، وإلا من تقاطع شعاع الماوس مع مستوى أفقي
      # عند ارتفاع نقطة المسك (عشان الركن العلوي يتحرك تحت الماوس صح)
      def raw_target(view, x, y)
        return nil unless @ip.valid?
        if @ground && @ip.degrees_of_freedom >= 3 && @grab
          ray = view.pickray(x, y)
          pt  = Geom.intersect_line_plane(ray, [@grab, Geom::Vector3d.new(0, 0, 1)])
          return pt if pt
        end
        @ip.position
      end

      # الأرضي: أفقي بس + ينزل على الأرض.  Shift: يتقفل على محور.
      def effective_delta(raw)
        v = @ground ? Geom::Vector3d.new(raw.x, raw.y, 0) : raw

        if @shift_active
          if @lock.nil? && v.length > MIN_LOCK_DISTANCE_MM.mm
            @lock = pick_axis(v)
          end
          v = @lock ? scale_vec(@lock, v.dot(@lock)) : Geom::Vector3d.new(0, 0, 0)
        end

        if @ground
          dz = ground_dz(v)
          v = Geom::Vector3d.new(v.x, v.y, dz)
        end
        v
      end

      # محاور الوحدة الأولى (أفقية) + الرأسي للوحدات العلوية
      def candidate_axes
        u = @units.first
        tr = u.transformation
        axes = [horiz(tr * Geom::Vector3d.new(1, 0, 0)), horiz(tr * Geom::Vector3d.new(0, 1, 0))]
        axes << Geom::Vector3d.new(0, 0, 1) unless @ground
        axes
      end

      def pick_axis(v)
        candidate_axes.max_by { |a| v.dot(a).abs }
      end

      def horiz(vec)
        len = Math.sqrt(vec.x * vec.x + vec.y * vec.y)
        len < 1e-9 ? Geom::Vector3d.new(1, 0, 0) : Geom::Vector3d.new(vec.x / len, vec.y / len, 0)
      end

      def scale_vec(vec, k)
        Geom::Vector3d.new(vec.x * k, vec.y * k, vec.z * k)
      end

      # الإزاحة الرأسية عشان الوحدة الأولى تقف على الأرض في مكانها الجديد
      def ground_dz(h)
        return 0.0 if @floor_faces.nil? || @floor_faces.empty?
        u  = @units.first
        c  = FP.world_center(u)
        Geometry::FloorSnap.dz_for(u, @floor_faces, c.x + h.x, c.y + h.y)
      end

      # ---------- نقطة المسك ----------
      def compute_grab_point
        u = @units.first
        return nil unless u
        x0, y0, x1, y1, _z0, z1 = box_bounds(u)
        left_x  = LEFT_IS_LOCAL_MAX_X ? x1 : x0
        right_x = LEFT_IS_LOCAL_MAX_X ? x0 : x1
        lx = (@corner == :left) ? left_x : right_x
        u.transformation * Geom::Point3d.new(lx, y0, z1)   # الركن العلوي الخلفي (y0 = الضهر)
      end

      # حدود الوحدة الفعلية [x0,y0,x1,y1,z0,z1] — لو مفيش هندسة نرجع للأبعاد الاسمية
      def box_bounds(unit)
        rb = FP.real_local_bounds(unit)
        return rb if rb
        x0, y0, x1, y1 = FP.local_bounds(unit)
        [x0, y0, x1, y1, 0.0, (FP::C::PLINTH_HEIGHT + FP.body_height_mm(unit)).mm]
      end

      # مكان نقطة المسك بعد اللف والإزاحة
      def moved_grab
        g = @grab
        u = @units.first
        if @fit_ang.abs > 0.0005 && u && u.valid?
          g = Geom::Transformation.rotation(FP.world_center(u), Z_AXIS, @fit_ang) * g
        end
        g + @delta
      end

      # 8 أركان صندوق الوحدة بعد اللف (ang) والإزاحة
      def box_corners(unit, delta, ang = 0.0)
        x0, y0, x1, y1, z0, z1 = box_bounds(unit)
        tr = unit.transformation
        rot = ang.abs > 0.0005 ? Geom::Transformation.rotation(FP.world_center(unit), Z_AXIS, ang) : nil
        pts = []
        [z0, z1].each do |z|
          [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].each do |x, y|
            pt = tr * Geom::Point3d.new(x, y, z)
            pt = rot * pt if rot
            pts << (pt + delta)
          end
        end
        pts
      end

      def box_edges(unit, delta, ang = 0.0)
        c = box_corners(unit, delta, ang)
        pairs = [[0, 1], [1, 2], [2, 3], [3, 0],
                 [4, 5], [5, 6], [6, 7], [7, 4],
                 [0, 4], [1, 5], [2, 6], [3, 7]]
        pairs.flat_map { |a, b| [c[a], c[b]] }
      end

      def commit_move(delta, view, fitted = false)
        ang = (@single && @fit_ang) ? @fit_ang.to_f : 0.0
        if delta.length < 0.01.mm && ang.abs < 0.0005
          @model.select_tool(nil)
          return
        end
        @model.start_operation('Cabinet Neo: نقل الوحدات', true)
        begin
          live = @units.select(&:valid?)
          if ang.abs > 0.0005 && live.size == 1
            # لف الضهر ناحية الحيط (حوالين المركز القديم — نفس اللي اتحسب في المعاينة) وبعدين الإزاحة
            c = FP.world_center(live.first)
            @model.entities.transform_entities(Geom::Transformation.rotation(c, Z_AXIS, ang), live)
          end
          @model.entities.transform_entities(Geom::Transformation.translation(delta), live)
          # لو وراها حيط قريب → الضهر يتلزق فيه أوتوماتيك
          snapped = 0
          if !fitted && defined?(::CabinetNeo::Geometry::UnitArranger)
            begin
              snapped = ::CabinetNeo::Geometry::UnitArranger.snap_back_to_wall(live)
            rescue StandardError => e
              puts "[MoveTool] wall snap: #{e.message}"
            end
          end
          @model.commit_operation
          Sketchup.status_text = fitted ? '✅ تم النقل (الضهر على الحيط)' : (snapped > 0 ? "✅ تم النقل + لزق الضهر في الحيط (#{snapped})" : '✅ تم نقل الوحدات')
        rescue StandardError => e
          @model.abort_operation
          puts "[MoveTool] #{e.message}"
          ::UI.messagebox("❌ تعذّر النقل: #{e.message}", ::MB_OK, 'Cabinet Neo')
        end
        @model.select_tool(nil)
        view.invalidate
      end
    end
  end
end

puts '[Cabinet Neo] ✅ move_tool.rb loaded'
