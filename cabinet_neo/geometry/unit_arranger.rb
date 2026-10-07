# encoding: UTF-8
# =============================================================================
# ترتيب الوحدات — v3
# =============================================================================
#   align_row(units)      محاذاة الوحدات جنب بعض
#   align_beside(u, t, s) محاذاة وحدة جنب وحدة تانية — BesideTool
#   align_to_wall(units)  محاذاة على الحيط (+ كورنر L على حيطين)
#   rotate(units, deg)    لف الوحدات
#
#   plan_back_rotation    زاوية اللف ناحية أقرب حيط
#   plan_move_fit         تصحيح الإزاحة (لزق + مغناطيس + منع اختراق)
#   neighbor_rects        مستطيلات الجيران للمغناطيس
#   align_corner_L_to_two_walls  ركن الكورنر L مع فلاتر
#
# v3: WALL_CLEARANCE_MM = 0.05 (تخفيض الفراغ) + فلاتر أركان الكورنر L
# v3.3: وحدة واحدة على الحيط — ما تدخلش جوه وحدة موجودة؛ تلزق جنبها من الناحيتين قبل الحيط التالي
# v3.1: كورنر L — تجاهل أركان حواف الباب (لازم الحيطتين يكملوا ناحية الأوضة)
#       + ترتيب ثابت للأركان عشان الزرار يلف على 4 أركان الأوضة بدل ما يفضل يتنقل جنب الباب
# =============================================================================

module CabinetNeo
  module Geometry
    module UnitArranger
      FP  = UnitFootprint
      Z_AXIS = Geom::Vector3d.new(0, 0, 1)

      MAX_WALL_DISTANCE_MM = 20000.0   # ⭐ v3.3: كان 4000 (4 متر) — دلوقتي 20 متر
      NEAR_WALL_MM         = 30.0      # حيط الوحدة ملزوقة فيه (≤ 3 سم) = مجرد لف في الركن، بيتتخطى
      WALL_CLEARANCE_MM    = 0.0       # ⭐ صفر: الوحدة تلزق في الحيط بالظبط (كان 0.05 مم وبيظهر كفراغ)
      MIN_WALL_FACE_AREA   = 10.0
      WALL_SNAP_MAX_MM     = 300.0
      SURFACE_FIX_MAX_MM   = 50.0
      SIDE_SNAP_MAX_MM     = 100.0     # لزق الجنب في حيط الكورنر (فراغ أقصاه 10 سم)

      MOVE_WALL_MAX_MM     = 4000.0
      MAGNET_MM            = 150.0
      ROTATE_WALL_MM       = 2000.0
      PUSH_MAX_RATIO       = 0.85

      # ---------------------------------------------------------------------
      # الوحدات المحددة
      # ---------------------------------------------------------------------
      def self.selected_units(model = Sketchup.active_model)
        model.selection.select { |e| FP.cabinet_unit?(e) || CountertopBuilder.legacy_unit?(e) }
      end

      def self.ok(msg);   { success: true,  message: msg }; end
      def self.fail(msg); { success: false, message: msg }; end

      # ---------------------------------------------------------------------
      # لف
      # ---------------------------------------------------------------------
      def self.rotate(units, degrees)
        return fail('حدد وحدة (أو أكتر) الأول.') if units.nil? || units.empty?
        model = Sketchup.active_model

        pivot =
          if units.size == 1
            FP.world_center(units.first)
          else
            combined_center(units)
          end

        model.start_operation('Cabinet Neo: لف الوحدات', true)
        begin
          tr = Geom::Transformation.rotation(pivot, Z_AXIS, degrees.to_f.degrees)
          model.entities.transform_entities(tr, units)
          model.commit_operation
          model.active_view.invalidate
          ok(degrees.to_f > 0 ? 'تم اللف ناحية الشمال' : 'تم اللف ناحية اليمين')
        rescue StandardError => e
          model.abort_operation
          puts "[UnitArranger] rotate: #{e.message}"
          fail("تعذّر اللف: #{e.message}")
        end
      end

      # ---------------------------------------------------------------------
      # محاذاة جنب بعض
      # ---------------------------------------------------------------------
      def self.align_row(units)
        return fail('حدد وحدتين على الأقل عشان نعمل محاذاة جنب بعض.') if units.nil? || units.size < 2
        model = Sketchup.active_model

        model.start_operation('Cabinet Neo: محاذاة الوحدات', true)
        begin
          anchor = pick_anchor(units)
          ah = FP.heading(anchor)

          units.each do |u|
            next if u.equal?(anchor)
            diff = normalize_angle(ah - FP.heading(u))
            next if diff.abs < 0.0005
            c = FP.world_center(u)
            model.entities.transform_entities(Geom::Transformation.rotation(c, Z_AXIS, diff), [u])
          end

          ux, uy = Math.cos(ah), Math.sin(ah)
          vx, vy = -Math.sin(ah), Math.cos(ah)

          info = units.map { |u| extents(u, ux, uy, vx, vy) }
          info.sort_by! { |i| i[:s0] }
          ref_t0 = info.find { |i| i[:unit].equal?(anchor) }[:t0]

          cursor = nil
          info.each do |i|
            ds = cursor.nil? ? 0.0 : (cursor - i[:s0])
            dt = ref_t0 - i[:t0]
            move = Geom::Vector3d.new(ux * ds + vx * dt, uy * ds + vy * dt, 0)
            if move.length > 0.01.mm
              model.entities.transform_entities(Geom::Transformation.translation(move), [i[:unit]])
            end
            cursor = i[:s1] + ds
          end

          model.commit_operation
          model.active_view.invalidate
          ok("تمت محاذاة #{units.size} وحدات جنب بعض")
        rescue StandardError => e
          model.abort_operation
          puts "[UnitArranger] align_row: #{e.message}"
          puts e.backtrace.first(5).join("\n")
          fail("تعذّرت المحاذاة: #{e.message}")
        end
      end

      # ---------------------------------------------------------------------
      # محاذاة وحدة جنب وحدة تانية
      # ---------------------------------------------------------------------
      def self.plan_beside(unit, target, side)
        th = FP.heading(target)

        if FP.subtype(target) == 'corner_L'
          if side == :arm2_end || side == :min_x
            rh, rside = normalize_angle(th - Math::PI / 2.0), :min_x
          else
            rh, rside = th, :max_x
          end
        else
          rh, rside = th, side
        end

        mh = rh
        mh = normalize_angle(rh + Math::PI / 2.0) if FP.subtype(unit) == 'corner_L' && rside == :max_x

        ang = normalize_angle(mh - FP.heading(unit))
        ang = 0.0 if ang.abs < 0.0005
        ux, uy = Math.cos(rh), Math.sin(rh)
        vx, vy = -Math.sin(rh), Math.cos(rh)

        c   = FP.world_center(unit)
        rot = Geom::Transformation.rotation(c, Z_AXIS, ang)
        upts = FP.real_world_corners(unit).map { |p| rot * p }
        tpts = FP.real_world_corners(target)

        u_s = upts.map { |p| p.x * ux + p.y * uy }
        u_t = upts.map { |p| p.x * vx + p.y * vy }
        t_s = tpts.map { |p| p.x * ux + p.y * uy }
        t_t = tpts.map { |p| p.x * vx + p.y * vy }

        ds = rside == :min_x ? (t_s.min - u_s.max) : (t_s.max - u_s.min)
        dt = t_t.min - u_t.min
        move = Geom::Vector3d.new(ux * ds + vx * dt, uy * ds + vy * dt, 0)

        { ang: ang, center: c, move: move, footprint: upts.map { |p| p.offset(move) } }
      end

      def self.align_beside(unit, target, side)
        return fail('الوحدة المحددة مش موجودة.') unless unit && unit.valid?
        return fail('الوحدة الهدف مش موجودة.')   unless target && target.valid?
        return fail('اختار وحدة تانية غير المحددة.') if unit.equal?(target)

        model = Sketchup.active_model
        model.start_operation('Cabinet Neo: محاذاة جنب وحدة', true)
        begin
          plan = plan_beside(unit, target, side)
          if plan[:ang].abs > 0.0005
            model.entities.transform_entities(
              Geom::Transformation.rotation(plan[:center], Z_AXIS, plan[:ang]), [unit])
          end
          if plan[:move].length > 0.01.mm
            model.entities.transform_entities(Geom::Transformation.translation(plan[:move]), [unit])
          end
          model.commit_operation
          model.active_view.invalidate
          ok("تمت المحاذاة جنب وحدة #{unit_no(target)}")
        rescue StandardError => e
          model.abort_operation
          puts "[UnitArranger] align_beside: #{e.message}"
          puts e.backtrace.first(5).join("\n")
          fail("تعذّرت المحاذاة: #{e.message}")
        end
      end

      # =====================================================================
      # نقل: دوال النقل (plan_back_rotation / plan_move_fit / neighbor_rects)
      # =====================================================================
      def self.neighbor_rects(unit, others, heading = nil)
        th = heading || FP.heading(unit)
        ux, uy = Math.cos(th), Math.sin(th)
        vx, vy = -Math.sin(th), Math.cos(th)
        upper = FP.category(unit) == 'upper'
        out = []
        others.each do |o|
          next unless o.valid? && !o.equal?(unit)
          next unless (FP.category(o) == 'upper') == upper
          q = normalize_angle(FP.heading(o) - th) / (Math::PI / 2.0)
          next unless (q - q.round).abs < 0.01
          unit_footprint_rects(o).each do |pts|
            ss = pts.map { |p| p.x * ux + p.y * uy }
            ts = pts.map { |p| p.x * vx + p.y * vy }
            out << { s0: ss.min, s1: ss.max, t0: ts.min, t1: ts.max }
          end
        end
        out
      end

      def self.unit_footprint_rects(u)
        tr = u.transformation
        rb = FP.real_local_bounds(u)
        rects =
          if FP.subtype(u) == 'corner_L'
            FP.local_rects(u, 0.0).map do |r|
              x0, y0, x1, y1 = r[:x0], r[:y0], r[:x1], r[:y1]
              if rb
                x0 = rb[0] if x0.abs < 1.mm
                y0 = rb[1] if r[:role] == :arm1
                x1 = rb[2] if r[:role] == :arm1
                y1 = rb[3] if r[:role] == :arm2
              end
              [x0, y0, x1, y1]
            end
          elsif rb
            [[rb[0], rb[1], rb[2], rb[3]]]
          else
            [FP.local_bounds(u)]
          end
        rects.map do |x0, y0, x1, y1|
          [[x0, y0], [x1, y0], [x1, y1], [x0, y1]].map { |x, y| tr * Geom::Point3d.new(x, y, 0) }
        end
      end

      def self.magnet_gap(pts, ux, uy, vx, vy, rects, thr)
        ss = pts.map { |p| p.x * ux + p.y * uy }
        ts = pts.map { |p| p.x * vx + p.y * vy }
        m_s0, m_s1 = ss.min, ss.max
        m_t0, m_t1 = ts.min, ts.max
        best = nil
        rects.each do |r|
          ov = [m_t1, r[:t1]].min - [m_t0, r[:t0]].max
          next if ov < 20.mm
          [r[:s0] - m_s1, r[:s1] - m_s0].each do |g|
            next if g.abs > thr
            best = g if best.nil? || g.abs < best.abs
          end
        end
        best
      end

      def self.back_gap_pts(pts, z0, h, bg, walls, max_gap)
        s_of = ->(p) { p.x * bg[0] + p.y * bg[1] }
        ss = pts.map { |p| s_of.call(p) }
        s_back, s_far = ss.max, ss.min
        extent = s_back - s_far
        return nil if extent < 1.mm
        par = [-bg[1], bg[0]]
        ps  = pts.map { |p| p.x * par[0] + p.y * par[1] }
        p_min, p_max = ps.min, ps.max
        zs = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]
        cand = walls.select { |w| (w[:n][0] * bg[0] + w[:n][1] * bg[1]).abs > 0.9995 }
        return nil if cand.empty?
        origin_s = s_far + 5.mm
        best = nil
        [0.1, 0.3, 0.5, 0.7, 0.9].each do |f|
          pp = p_min + (p_max - p_min) * f
          ox = bg[0] * origin_s + par[0] * pp
          oy = bg[1] * origin_s + par[1] * pp
          zs.each do |z|
            o = Geom::Point3d.new(ox, oy, z)
            t = nil
            cand.each do |w|
              tt = ray_hit(o, bg, w)
              t = tt if tt && (t.nil? || tt < t)
            end
            next unless t
            delta = (origin_s + t) - s_back
            next if delta < -extent * PUSH_MAX_RATIO || delta > max_gap
            best = delta if best.nil? || delta < best
          end
        end
        best
      end

      def self.plan_move_fit(unit, delta, walls, rects, magnet = true, ang = 0.0, snap_wall = true)
        pts0 = FP.real_world_corners(unit)
        fx, fy = FP.front_dir(unit)
        th = FP.heading(unit)
        if ang.abs > 1e-9
          rot  = Geom::Transformation.rotation(FP.world_center(unit), Z_AXIS, ang)
          pts0 = pts0.map { |p| rot * p }
          ca, sa = Math.cos(ang), Math.sin(ang)
          fx, fy = fx * ca - fy * sa, fx * sa + fy * ca
          th += ang
        end
        base = pts0.map { |p| p.offset(delta) }
        h    = FP.body_height_mm(unit).mm
        z0   = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z + delta.z + FP::C::PLINTH_HEIGHT.mm
        bg = [-fx, -fy]
        ux, uy = Math.cos(th), Math.sin(th)
        vx, vy = -Math.sin(th), Math.cos(th)
        tx = 0.0
        ty = 0.0
        cur = lambda { base.map { |p| Geom::Point3d.new(p.x + tx, p.y + ty, p.z) } }
        has_walls = walls && !walls.empty?

        if has_walls && snap_wall
          g = back_gap_pts(cur.call, z0, h, bg, walls, ROTATE_WALL_MM.mm)
          if g
            gap = g - WALL_CLEARANCE_MM.mm
            tx += bg[0] * gap
            ty += bg[1] * gap
            # كورنر: لو الضهر لزق، الجنب القريب من حيط تاني يتلزق كمان
            [[-fy, fx], [fy, -fx]].each do |sd|
              sg = back_gap_pts(cur.call, z0, h, sd, walls, SIDE_SNAP_MAX_MM.mm)
              next unless sg
              sgap = sg - WALL_CLEARANCE_MM.mm
              next if sgap <= 0.01.mm
              tx += sd[0] * sgap
              ty += sd[1] * sgap
            end
          end
        end

        if magnet && rects && !rects.empty?
          g = magnet_gap(cur.call, ux, uy, vx, vy, rects, MAGNET_MM.mm)
          if g
            tx += ux * g
            ty += uy * g
          end
        end

        if has_walls
          2.times do
            changed = false
            [bg, [-fy, fx], [fy, -fx]].each do |d|
              pen = direction_penetration_pts(cur.call, z0, h, d, walls)
              next if pen <= 0.01.mm
              tx -= d[0] * pen
              ty -= d[1] * pen
              changed = true
            end
            break unless changed
          end
        end
        Geom::Vector3d.new(tx, ty, 0)
      end

      def self.plan_back_rotation(unit, delta, walls, max_mm = ROTATE_WALL_MM)
        return 0.0 if walls.nil? || walls.empty?
        c  = FP.world_center(unit)
        cx = c.x + delta.x
        cy = c.y + delta.y
        h  = FP.body_height_mm(unit).mm
        z0 = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z + delta.z + FP::C::PLINTH_HEIGHT.mm
        zs = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]

        rb = FP.real_local_bounds(unit)
        lb = FP.local_bounds(unit)
        dx = (rb ? (rb[2] - rb[0]) : (lb[2] - lb[0])).mm
        dy = (rb ? (rb[3] - rb[1]) : (lb[3] - lb[1])).mm
        limit = max_mm.mm + [dx, dy].min / 2.0

        span = [dx, dy].max
        best = nil
        walls.each do |w|
          side = w[:n][0] * cx + w[:n][1] * cy - w[:c]
          t = side.abs
          next if t < 1e-6 || t > limit
          next if best && t >= best[:t]
          d   = side > 0 ? [-w[:n][0], -w[:n][1]] : [w[:n][0], w[:n][1]]
          par = [-d[1], d[0]]
          hit = [0.0, -0.3, 0.3, -0.6, 0.6].any? do |k|
            ox = cx + par[0] * span * k
            oy = cy + par[1] * span * k
            zs.any? { |z| ray_hit(Geom::Point3d.new(ox, oy, z), d, w) }
          end
          next unless hit
          best = { t: t, d: d }
        end
        return 0.0 unless best

        fx, fy = FP.front_dir(unit)
        ang = normalize_angle(Math.atan2(best[:d][1], best[:d][0]) - Math.atan2(-fy, -fx))
        ang.abs < 0.0005 ? 0.0 : ang
      end

      def self.direction_penetration_pts(pts, z0, h, d, walls)
        s_of = ->(p) { p.x * d[0] + p.y * d[1] }
        ss = pts.map { |p| s_of.call(p) }
        s_ext, s_far = ss.max, ss.min
        extent = s_ext - s_far
        return 0.0 if extent < 1.mm

        par = [-d[1], d[0]]
        ps  = pts.map { |p| p.x * par[0] + p.y * par[1] }
        p_min, p_max = ps.min, ps.max

        zs = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]
        cand = walls.select { |w| (w[:n][0] * d[0] + w[:n][1] * d[1]).abs > 0.9 }
        return 0.0 if cand.empty?

        origin_s = s_far + 5.mm
        worst = 0.0
        [0.1, 0.3, 0.5, 0.7, 0.9].each do |f|
          pp = p_min + (p_max - p_min) * f
          ox = d[0] * origin_s + par[0] * pp
          oy = d[1] * origin_s + par[1] * pp
          zs.each do |z|
            o = Geom::Point3d.new(ox, oy, z)
            best = nil
            cand.each do |w|
              t = ray_hit(o, d, w)
              best = t if t && (best.nil? || t < best)
            end
            next unless best
            delta = s_ext - (origin_s + best)
            next if delta <= 0.05.mm || delta > extent * PUSH_MAX_RATIO
            worst = delta if delta > worst
          end
        end
        worst > 0 ? worst + WALL_CLEARANCE_MM.mm : 0.0
      end

      # =====================================================================
      # أدوات الحيطان
      # =====================================================================
      def self.first_wall_hit(walls, o, d)
        best = nil
        facing = false
        walls.each do |w|
          t = ray_hit(o, d, w)
          next unless t
          if best.nil? || t < best
            best = t
            facing = (w[:n][0] * d[0] + w[:n][1] * d[1]) < 0
          end
        end
        best ? [best, facing] : nil
      end

      def self.inside_room?(walls, x, y, z, axes)
        return true if walls.nil? || walls.empty?
        o = Geom::Point3d.new(x, y, z)
        axes.count do |d|
          r = first_wall_hit(walls, o, d)
          r && r[1]
        end >= 3
      end

      # ⭐ v3: هل النقطة على وش الحيط فعلاً (مش على امتداده)؟
      def self.on_wall?(pt, w)
        return false if pt.z < w[:zmin] - 1.mm || pt.z > w[:zmax] + 1.mm
        lp = w[:inv] * pt
        res = w[:face].classify_point(lp)
        [Sketchup::Face::PointInside, Sketchup::Face::PointOnFace,
         Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include?(res)
      rescue StandardError
        false
      end

      def self.snap_back_to_wall(units, max_mm = WALL_SNAP_MAX_MM, walls = nil)
        model = Sketchup.active_model
        walls ||= collect_wall_faces(model)
        return 0 if walls.empty?
        max = max_mm.mm
        fix = SURFACE_FIX_MAX_MM.mm
        count = 0

        units.each do |u|
          next unless u.valid?
          fx, fy = FP.front_dir(u)
          bg = [-fx, -fy]
          facing = walls.select { |w| (w[:n][0] * bg[0] + w[:n][1] * bg[1]) < -0.9995 }
          next if facing.empty?

          pts = FP.real_world_corners(u)
          s_back = pts.map { |p| p.x * bg[0] + p.y * bg[1] }.max
          par = [-bg[1], bg[0]]
          ps  = pts.map { |p| p.x * par[0] + p.y * par[1] }
          p_min, p_max = ps.min, ps.max

          h  = FP.body_height_mm(u).mm
          z0 = (u.transformation * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
          zs = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]
          origin_s = s_back - fix - 10.mm

          best = nil
          [0.1, 0.3, 0.5, 0.7, 0.9].each do |f|
            pp = p_min + (p_max - p_min) * f
            ox = bg[0] * origin_s + par[0] * pp
            oy = bg[1] * origin_s + par[1] * pp
            zs.each do |z|
              o = Geom::Point3d.new(ox, oy, z)
              t = nil
              facing.each do |w|
                tt = ray_hit(o, bg, w)
                t = tt if tt && (t.nil? || tt < t)
              end
              next unless t
              delta = (origin_s + t) - s_back
              next if delta < -fix || delta > max
              best = delta if best.nil? || delta < best
            end
          end
          next unless best

          gap = best - WALL_CLEARANCE_MM.mm
          next if gap.abs < 0.1.mm
          mv = Geom::Vector3d.new(bg[0] * gap, bg[1] * gap, 0)
          model.entities.transform_entities(Geom::Transformation.translation(mv), [u])
          count += 1
          snap_sides_to_wall(model, u, walls)
        end
        count
      end

      # يلزّق جنب الوحدة في حيط الكورنر لو فيه فراغ صغير (≤ SIDE_SNAP_MAX_MM)
      def self.snap_sides_to_wall(model, u, walls)
        fx, fy = FP.front_dir(u)
        h  = FP.body_height_mm(u).mm
        z0 = (u.transformation * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
        [[-fy, fx], [fy, -fx]].each do |sd|
          sg = back_gap_pts(FP.real_world_corners(u), z0, h, sd, walls, SIDE_SNAP_MAX_MM.mm)
          next unless sg
          sgap = sg - WALL_CLEARANCE_MM.mm
          next if sgap <= 0.1.mm
          mv = Geom::Vector3d.new(sd[0] * sgap, sd[1] * sgap, 0)
          model.entities.transform_entities(Geom::Transformation.translation(mv), [u])
        end
      end

      # =====================================================================
      # مكان الوحدة الجديدة
      # =====================================================================
      def self.plan_new_unit(model, w, d, h, category = 'lower')
        origin_tr = Geom::Transformation.new(Geom::Point3d.new(0, 0, 0))
        walls = collect_wall_faces(model)
        z_mid = FP::C::PLINTH_HEIGHT.mm + h * 0.5
        all   = model.entities.select { |e| FP.cabinet_unit?(e) }

        refs = all.sort_by { |u| -unit_no(u) }
        ref = refs.find do |u|
          th = FP.heading(u)
          axes = [[Math.cos(th), Math.sin(th)], [-Math.sin(th), Math.cos(th)],
                  [-Math.cos(th), -Math.sin(th)], [Math.sin(th), -Math.cos(th)]]
          c = FP.world_center(u)
          inside_room?(walls, c.x, c.y, z_mid, axes)
        end

        unless ref
          return origin_tr if walls.empty?
          xs = []; ys = []
          walls.each do |wl|
            tr = wl[:inv].inverse
            wl[:face].vertices.each { |vx| q = tr * vx.position; xs << q.x; ys << q.y }
          end
          cx = (xs.min + xs.max) / 2.0
          cy = (ys.min + ys.max) / 2.0
          axes = [[1, 0], [0, 1], [-1, 0], [0, -1]]
          return origin_tr unless inside_room?(walls, cx, cy, z_mid, axes)
          o  = Geom::Point3d.new(cx, cy, z_mid)
          rw = first_wall_hit(walls, o, [-1, 0])
          rs = first_wall_hit(walls, o, [0, -1])
          return origin_tr unless rw && rw[1] && rs && rs[1]
          return Geom::Transformation.new(
            Geom::Point3d.new(cx - rw[0] + WALL_CLEARANCE_MM.mm, cy - rs[0] + WALL_CLEARANCE_MM.mm, 0))
        end

        th = FP.heading(ref)
        u = [Math.cos(th), Math.sin(th)]
        v = [-Math.sin(th), Math.cos(th)]
        s_of = ->(p) { p.x * u[0] + p.y * u[1] }
        t_of = ->(p) { p.x * v[0] + p.y * v[1] }
        rp = FP.real_world_corners(ref)
        ref_s0 = rp.map { |p| s_of.call(p) }.min
        ref_s1 = rp.map { |p| s_of.call(p) }.max
        t_back = rp.map { |p| t_of.call(p) }.min

        upper = category.to_s == 'upper'
        others = all.select { |o| (FP.category(o) == 'upper') == upper }
        spans = others.map do |o|
          pp = FP.real_world_corners(o)
          ss = pp.map { |q| s_of.call(q) }
          tt = pp.map { |q| t_of.call(q) }
          { s0: ss.min, s1: ss.max, t0: tt.min, t1: tt.max }
        end
        tol = 5.mm

        find_start = lambda do |sign|
          s_start = sign > 0 ? ref_s1 : ref_s0 - w
          result = nil
          25.times do
            blk = spans.find do |sp|
              sp[:s0] < s_start + w - tol && sp[:s1] > s_start + tol &&
                sp[:t0] < t_back + d - tol && sp[:t1] > t_back + tol
            end
            if blk
              s_start = sign > 0 ? blk[:s1] : blk[:s0] - w
              next
            end
            cs = s_start + w / 2.0
            ct = t_back + d / 2.0
            cx = u[0] * cs + v[0] * ct
            cy = u[1] * cs + v[1] * ct
            dir = [u[0] * sign, u[1] * sign]
            hit = walls.empty? ? true : first_wall_hit(walls, Geom::Point3d.new(cx, cy, z_mid), dir)
            ok = hit == true || (hit && hit[1] && hit[0] >= w / 2.0 - tol)
            result = s_start if ok
            break
          end
          result
        end

        s_start = find_start.call(1) || find_start.call(-1)
        unless s_start
          puts '[Cabinet Neo] ⚠️ مفيش مكان فاضي — اتحطت جنب آخر وحدة'
          s_start = ref_s1
        end

        org = Geom::Point3d.new(u[0] * s_start + v[0] * t_back, u[1] * s_start + v[1] * t_back, 0)
        Geom::Transformation.new(org) * Geom::Transformation.rotation(Geom::Point3d.new(0, 0, 0), Z_AXIS, th)
      end

      def self.extents(unit, ux, uy, vx, vy)
        pts = FP.world_corners(unit)
        ss = pts.map { |p| p.x * ux + p.y * uy }
        ts = pts.map { |p| p.x * vx + p.y * vy }
        { unit: unit, s0: ss.min, s1: ss.max, t0: ts.min, t1: ts.max }
      end

      def self.pick_anchor(units)
        buckets = units.group_by { |u| (FP.heading(u).radians.round) % 360 }
        best = buckets.values.max_by { |arr| [arr.size, -arr.map { |u| unit_no(u) }.min] }
        best.min_by { |u| unit_no(u) }
      end

      def self.unit_no(u)
        u.definition.get_attribute('CabinetNeo', 'unit_number', 0).to_i
      end

      def self.normalize_angle(a)
        a -= 2 * Math::PI while a > Math::PI
        a += 2 * Math::PI while a < -Math::PI
        a
      end

      def self.combined_center(units)
        pts = units.flat_map { |u| FP.world_corners(u) }
        xs = pts.map(&:x); ys = pts.map(&:y)
        Geom::Point3d.new((xs.min + xs.max) / 2.0, (ys.min + ys.max) / 2.0, 0)
      end

      # =====================================================================
      # محاذاة على الحيط
      # =====================================================================
      def self.cycle_state
        @cycle_state ||= {}
      end

      def self.align_to_wall(units)
        return fail('حدد وحدة (أو أكتر) الأول.') if units.nil? || units.empty?
        model = Sketchup.active_model

        walls = collect_wall_faces(model)
        return fail("مفيش حيط في الموديل.\n\nارسم الحيطان كأوجه رأسية (Faces).") if walls.empty?

        model.start_operation('Cabinet Neo: محاذاة على الحيط', true)
        done = 0
        label = nil
        blocked = false
        begin
          units.each do |u|
            # ⭐ كورنر L → محاذاة على حيطين
            if FP.subtype(u) == 'corner_L'
              ok = align_corner_L_to_two_walls(model, u, walls)
              if ok
                label = 'كورنر على حيطين'
                done += 1
                next
              end
              # مفيش ركن مناسب → كمّل وحاذيه على أقرب حيط
            end

            cands = wall_candidates(u, walls)
            next if cands.empty?

            # ⭐ v3.3: وحدة واحدة → تتفادى الوحدات الموجودة وتلزق جنبها
            if units.size == 1
              msg1 = place_single_unit_on_wall(model, u, cands, walls, units)
              if msg1
                label = msg1
                done += 1
              else
                blocked = true
              end
              next
            end

            pick, idx = choose_candidate(u, cands)
            align_unit_to_wall(model, u, pick, walls)
            cycle_state[u.entityID] = { key: pick[:key], tr: u.transformation.to_a }
            label = "الحيط #{idx + 1} من #{cands.size}"
            done += 1
          end
          if done.zero?
            model.abort_operation
            return fail('كل الحيطان القريبة مشغولة بوحدات تانية — مفيش مكان فاضي للوحدة.') if blocked
            return fail('مفيش حيط قريب من الوحدات المحددة (لازم جوه 20 متر).')
          end
          model.commit_operation
          model.active_view.invalidate
          msg = "تمت محاذاة #{done} وحدة على الحيط"
          msg += " — #{label}" if units.size == 1 && label
          ok(msg)
        rescue StandardError => e
          model.abort_operation
          puts "[UnitArranger] align_to_wall: #{e.message}"
          puts e.backtrace.first(6).join("\n")
          fail("تعذّرت المحاذاة على الحيط: #{e.message}")
        end
      end

      # ⭐ v3: كورنر L → أقرب ركن حقيقي في الأوضة
      def self.corner_cycle_state
        @corner_cycle_state ||= {}
      end

      # ⭐ الجهة الداخلية لوش الحيطة: +1 لو الاتجاه n ناحية الأوضة، -1 لو العكس، nil لو مش محددة
      #    (بنجرب نقطة 50 مم قدام الوش على الناحيتين ونشوف أنهي جوه الأوضة)
      def self.interior_sign(walls, w, z)
        @interior_cache ||= {}
        key = [w[:face].entityID, z.round(2)]
        return @interior_cache[key] if @interior_cache.key?(key)
        res = nil
        begin
          tr  = w[:inv].inverse
          ctr = tr * w[:face].bounds.center
          n   = w[:n]
          axes = [[1, 0], [0, 1], [-1, 0], [0, -1]]
          ins = [1, -1].map do |sg|
            px = ctr.x + n[0] * sg * 50.mm
            py = ctr.y + n[1] * sg * 50.mm
            inside_room?(walls, px, py, z, axes)
          end
          res = 1 if ins[0] && !ins[1]
          res = -1 if ins[1] && !ins[0]
        rescue StandardError
          res = nil
        end
        @interior_cache[key] = res
      end

      # مسح الكاش (بيتنادى في بداية كل محاذاة عشان الحيطان ممكن تتعدل)
      def self.reset_interior_cache
        @interior_cache = {}
      end

      def self.align_corner_L_to_two_walls(model, unit, walls)
        reset_interior_cache
        c  = FP.world_center(unit)
        max_t = MAX_WALL_DISTANCE_MM.mm

        # ⭐ غرف بأكتر من 4 حيطان (مش محدبة): اتجاه كل حيطة لازم يتحدد من جهة الأوضة نفسها
        #    مش من مكان الوحدة — وإلا ركن بيظهر ويختفي حسب مكان الوحدة (4 أركان / 5 أركان)
        z_probe = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z +
                  FP::C::PLINTH_HEIGHT.mm + 300.mm
        cands = []
        walls.each do |w|
          n = w[:n]
          side = n[0] * c.x + n[1] * c.y - w[:c]
          t = side.abs
          next if t < 1e-6 || t > max_t
          sgn = interior_sign(walls, w, z_probe)
          next if sgn.nil?
          nf  = sgn > 0 ? n : [-n[0], -n[1]]
          off = sgn > 0 ? w[:c] : -w[:c]
          cands << { normal: nf, plane_c: off, t: t, w: w }
        end
        if cands.size < 2
          # مفيش تحديد للجهة الداخلية (موديل مفتوح مثلاً) → الطريقة القديمة (حسب مكان الوحدة)
          cands = []
          walls.each do |w|
            n = w[:n]
            side = n[0] * c.x + n[1] * c.y - w[:c]
            t = side.abs
            next if t < 1e-6 || t > max_t
            nf  = side > 0 ? n : [-n[0], -n[1]]
            off = side > 0 ? w[:c] : -w[:c]
            cands << { normal: nf, plane_c: off, t: t, w: w }
          end
        end
        return false if cands.size < 2

        ext = 500.mm   # أقل امتداد للحيطتين من الركن (يستبعد حواف الباب/السمك)

        z_mid = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z +
                FP::C::PLINTH_HEIGHT.mm + 300.mm
        pairs = []
        cands.each_with_index do |a, i|
          cands.each_with_index do |b, j|
            next if j <= i
            dot = a[:normal][0] * b[:normal][0] + a[:normal][1] * b[:normal][1]
            next if dot.abs > 0.15
            det = a[:normal][0] * b[:normal][1] - a[:normal][1] * b[:normal][0]
            next if det.abs < 1e-6
            px = (a[:plane_c] * b[:normal][1] - a[:normal][1] * b[:plane_c]) / det
            py = (a[:normal][0] * b[:plane_c] - a[:plane_c] * b[:normal][0]) / det

            # ⭐ v3.2: فحص الركن بنقطة اختبار جوه الأوضة (مش على الركن نفسه) — أثبت
            next unless corner_valid?(walls, a, b, px, py, z_mid, ext)

            dist = Math.sqrt((px - c.x)**2 + (py - c.y)**2)
            key = [px.round(2) + 0.0, py.round(2) + 0.0]   # +0.0 يلغي -0.0 (كان بيعمل ركن مكرر)
            pairs << { wa: a, wb: b, corner: [px, py], dist: dist, key: key }
          end
        end
        return false if pairs.empty?

        pairs.uniq! { |p| p[:key] }

        # ⭐ v3.1: ترتيب ثابت حوالين مركز الأركان (مش بالمسافة من الوحدة)
        # عشان الدوران ما يفضلش يتنقل بين ركنين قريبين من بعض.
        cx = pairs.sum { |pr| pr[:corner][0] } / pairs.size
        cy = pairs.sum { |pr| pr[:corner][1] } / pairs.size
        pairs.sort_by! { |pr| Math.atan2(pr[:corner][1] - cy, pr[:corner][0] - cx) }

        st = corner_cycle_state[unit.entityID]
        cur_idx = nil
        if st && same_tr?(st[:tr], unit.transformation.to_a)
          cur_idx = pairs.index { |pr| pr[:key] == st[:key] }
        end
        next_idx =
          if cur_idx
            (cur_idx + 1) % pairs.size
          else
            pairs.each_with_index.min_by { |pr, _| pr[:dist] }[1]   # أول ضغطة: أقرب ركن
          end
        chosen = pairs[next_idx]
        wa = chosen[:wa]
        wb = chosen[:wb]
        px, py = chosen[:corner]

        y_axis = Geom::Vector3d.new(wa[:normal][0], wa[:normal][1], 0)
        x_axis = Geom::Vector3d.new(wb[:normal][0], wb[:normal][1], 0)
        if x_axis.cross(y_axis).z < 0
          x_axis, y_axis = y_axis, x_axis
        end
        # ⭐ v3.2: محاور متعامدة تماماً (الحيطان ممكن تكون مايلة شوية → كان بيحصل ميل/فراغ)
        y_axis.normalize!
        dd = x_axis.x * y_axis.x + x_axis.y * y_axis.y
        x_axis = Geom::Vector3d.new(x_axis.x - y_axis.x * dd, x_axis.y - y_axis.y * dd, 0)
        x_axis.normalize!
        z_axis = Geom::Vector3d.new(0, 0, 1)

        current_origin = unit.transformation.origin
        corner_pt = Geom::Point3d.new(px, py, current_origin.z)
        target_tr = Geom::Transformation.axes(corner_pt, x_axis, y_axis, z_axis)

        delta = target_tr * unit.transformation.inverse
        model.entities.transform_entities(delta, [unit])

        # ⭐ v3.2: قفل أي فراغ صغير (لحد 3 سم) بين الوحدة وكل حيطة من الاتنين
        # الركن اتأكد إنه حقيقي → نقفل الفراغ لحد SIDE_SNAP_MAX_MM (كان 3 سم) في الحيطتين
        flush_to_wall(model, unit, wa, SIDE_SNAP_MAX_MM.mm)
        flush_to_wall(model, unit, wb, SIDE_SNAP_MAX_MM.mm)
        push_out_of_walls(model, unit, walls)
        # تثبيت أخير بعد الدفع: أي فراغ فاضل يتقفل
        flush_to_wall(model, unit, wa, SIDE_SNAP_MAX_MM.mm)
        flush_to_wall(model, unit, wb, SIDE_SNAP_MAX_MM.mm)

        # تشخيص: زاوية الحيطتين + عدد الوحدات والفراغ عند طرفي كل ذراع
        begin
          dotp = wa[:normal][0] * wb[:normal][0] + wa[:normal][1] * wb[:normal][1]
          ang_dev = Math.acos([[dotp, 1.0].min, -1.0].max).radians - 90.0
          pts = FP.real_world_corners(unit)
          rep = [wa, wb].map do |cw|
            bgx, bgy = -cw[:normal][0], -cw[:normal][1]
            ss = pts.map { |q| q.x * bgx + q.y * bgy }
            sm = ss.max
            gaps = pts.select { |q| (q.x * bgx + q.y * bgy) > sm - 1.mm }.map do |q|
              (-cw[:plane_c] - (q.x * bgx + q.y * bgy)).to_mm.round(2)
            end
            gaps.inspect
          end
          puts format('[UnitArranger][diag] زاوية الحيطتين: %.2f° عن 90 | فراغ حيط A %s | حيط B %s',
                      ang_dev, rep[0], rep[1])
        rescue StandardError => e
          puts "[UnitArranger][diag] #{e.message}"
        end

        corner_cycle_state[unit.entityID] = { key: chosen[:key], tr: unit.transformation.to_a }

        puts format('[UnitArranger] corner L → ركن (%.1f, %.1f) من %d أركان',
                    px, py, pairs.size)
        true
      rescue StandardError => e
        puts "[UnitArranger] align_corner_L_to_two_walls: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        false
      end

      # ⭐ v3.2: ركن حقيقي = الحيطتين بيكملوا ناحية الأوضة + نقطة جوه الركن فعلاً جوه الأوضة
      def self.corner_valid?(walls, a, b, px, py, z, ext)
        return false unless wall_extends?(px, py, z, a, b, ext)
        return false unless wall_extends?(px, py, z, b, a, ext)
        na = a[:normal]
        nb = b[:normal]
        probe_x = px + (na[0] + nb[0]) * 50.mm
        probe_y = py + (na[1] + nb[1]) * 50.mm
        axes = [[-na[0], -na[1]], [-nb[0], -nb[1]], [na[0], na[1]], [nb[0], nb[1]]]
        inside_room?(walls, probe_x, probe_y, z, axes)
      end

      # الحيطة cand بتكمل من نقطة الركن ناحية الحيطة التانية (بشعاع ray_hit — نفس طريقة wall_candidates)
      def self.wall_extends?(px, py, z, cand, other, ext)
        n = cand[:normal]
        tx = -n[1]
        ty = n[0]
        if tx * other[:normal][0] + ty * other[:normal][1] < 0
          tx = -tx
          ty = -ty
        end
        d = [-n[0], -n[1]]
        [0.05, 0.8, 1.0].all? do |k|
          o = Geom::Point3d.new(px + tx * ext * k + n[0] * 30.mm,
                                py + ty * ext * k + n[1] * 30.mm, z)
          t = ray_hit(o, d, cand[:w])
          t && t < 60.mm
        end
      end

      # يلزّق الوحدة في الحيطة لو الفراغ (أو الاختراق) صغير
      def self.flush_to_wall(model, unit, cand, max_gap)
        n  = cand[:normal]
        bg = [-n[0], -n[1]]
        pts = FP.real_world_corners(unit)
        back_most = pts.map { |p| p.x * bg[0] + p.y * bg[1] }.max
        gap = -cand[:plane_c] - back_most - WALL_CLEARANCE_MM.mm
        return 0.0 if gap.abs < 0.01.mm || gap.abs > max_gap
        vec = Geom::Vector3d.new(bg[0] * gap, bg[1] * gap, 0)
        model.entities.transform_entities(Geom::Transformation.translation(vec), [unit])
        gap
      end

      # =====================================================================
      # ⭐ v3.3: وحدة واحدة على الحيط مع تفادي الوحدات الموجودة
      # =====================================================================
      def self.neo_units(model)
        model.entities.select { |e| FP.cabinet_unit?(e) }
      end

      def self.place_single_unit_on_wall(model, u, cands, walls, selected)
        sel_ids = selected.map(&:entityID)
        others  = neo_units(model).reject { |o| sel_ids.include?(o.entityID) }

        st = cycle_state[u.entityID]
        pose_ok = st && same_pose?(st[:tr], u.transformation.to_a)

        # 1) لسه الناحية التانية من الوحدة الجارة → كمّل عليها قبل الحيط التالي
        if pose_ok && st[:nslots].to_i == 2 && st[:visited].to_i == 1
          i = cands.index { |c| c[:key] == st[:key] }
          if i
            res = place_on_wall(model, u, cands[i], walls, others, true)
            if res
              record_cycle(u, cands[i], res, 2)
              return "الحيط #{i + 1} من #{cands.size} — الناحية التانية من الوحدة الجارة"
            end
          end
        end

        # 2) الحيط التالي (ويتخطى الحيطان اللي مفيهاش مكان فاضي)
        _pick, idx = choose_candidate(u, cands)
        cands.size.times do |k|
          i = (idx + k) % cands.size
          res = place_on_wall(model, u, cands[i], walls, others, false)
          next unless res
          record_cycle(u, cands[i], res, 1)
          msg = "الحيط #{i + 1} من #{cands.size}"
          msg += " — ملزوقة جنب وحدة موجودة" if res[:nslots] > 0
          return msg
        end
        nil
      end

      def self.record_cycle(u, cand, res, visited)
        cycle_state[u.entityID] = { key: cand[:key], tr: u.transformation.to_a,
                                    nslots: res[:nslots], visited: visited }
      end

      # يحاذي الوحدة على الحيط، ولو دخلت في وحدة تانية يزحزحها جنبها (continuing = الناحية التانية)
      def self.place_on_wall(model, u, cand, walls, others, continuing)
        orig = u.transformation
        align_unit_to_wall(model, u, cand, walls)
        return { nslots: 0 } if others.empty?

        info = beside_slots(u, others, walls, continuing)
        return { nslots: 0 } if info.nil?

        if info[:shifts].empty?
          u.transformation = orig      # مفيش مكان فاضي على الحيط ده — ارجع زي ما كانت
          return nil
        end

        shift = continuing ? info[:shifts].max_by(&:abs) : info[:shifts].min_by(&:abs)
        if shift.abs > 0.01.mm
          vec = Geom::Vector3d.new(info[:ux] * shift, info[:uy] * shift, 0)
          model.entities.transform_entities(Geom::Transformation.translation(vec), [u])
        end
        puts format('[UnitArranger] جنب وحدة: %d مكان فاضي — إزاحة %.1f مم', info[:shifts].size, shift.to_mm)
        { nslots: info[:shifts].size }
      end

      # الأماكن الفاضية على جنبي الوحدة/الوحدات اللي الوحدة داخلة فيها (على طول الحيط).
      # بترجّع nil لو مفيش تداخل، أو { ux:, uy:, shifts: [...] } (shifts فاضية = مفيش مكان).
      # touch=true → الوحدة الملزوقة (من غير تداخل) تتحسب برضه (للناحية التانية).
      def self.beside_slots(u, others, walls, touch)
        rects = neighbor_rects(u, others)
        return nil if rects.empty?

        th = FP.heading(u)
        ux, uy = Math.cos(th), Math.sin(th)
        vx, vy = -Math.sin(th), Math.cos(th)
        pts = FP.real_world_corners(u)
        ss = pts.map { |p| p.x * ux + p.y * uy }
        ts = pts.map { |p| p.x * vx + p.y * vy }
        s0, s1, t0, t1 = ss.min, ss.max, ts.min, ts.max

        row = rects.select { |r| [t1, r[:t1]].min - [t0, r[:t0]].max > 1.mm }
        hit = lambda do |a0, a1, tol|
          row.select { |r| [a1, r[:s1]].min - [a0, r[:s0]].max > tol }
        end
        return nil if hit.call(s0, s1, touch ? -2.mm : 1.mm).empty?

        z0 = (u.transformation * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
        h  = FP.body_height_mm(u).mm

        shifts = []
        [:low, :high].each do |side|
          a0, a1 = s0, s1
          shift  = 0.0
          tol    = touch ? -2.mm : 1.mm
          done   = false
          12.times do
            bl = hit.call(a0, a1, tol)
            if bl.empty?
              done = true
              break
            end
            delta = side == :low ? (bl.map { |r| r[:s0] }.min - a1) : (bl.map { |r| r[:s1] }.max - a0)
            a0 += delta
            a1 += delta
            shift += delta
            tol = 1.mm
          end
          next unless done

          if shift.abs > 0.01.mm
            mv  = Geom::Vector3d.new(ux * shift, uy * shift, 0)
            d   = shift > 0 ? [ux, uy] : [-ux, -uy]
            moved = pts.map { |p| p.offset(mv) }
            next if direction_penetration_pts(moved, z0, h, d, walls) > 2.mm
          end
          shifts << shift unless shifts.any? { |x| (x - shift).abs < 1.mm }
        end

        { ux: ux, uy: uy, shifts: shifts }
      end

      def self.same_tr?(a, b)
        return false unless a && b && a.size == b.size
        a.each_with_index.all? { |v, i| (v - b[i]).abs < 1e-6 }
      end

      # ⭐ v3.3: اختيار الحيط التالي
      #  - الوحدة مضهورة على حيط دلوقتي (بالهندسة، مش بمقارنة الـ transformation) → الحيط اللي بعده
      #  - الحيط اللي الوحدة ملزوقة فيه فعلاً (ركن) بيتتخطى — لأنه مجرد لف في المكان (10 مم)
      #  - لو مفيش حيط حالي → أقرب حيط
      def self.choose_candidate(unit, cands)
        cur = cands.index { |c| flush_with?(unit, c, 15.mm, 0.998) }
        if cur.nil?
          st = cycle_state[unit.entityID]
          if st && same_pose?(st[:tr], unit.transformation.to_a)
            cur = cands.index { |c| c[:key] == st[:key] }
          end
        end

        if cur && cands.size > 1
          order = (1...cands.size).map { |k| (cur + k) % cands.size }
          n = order.find { |i| wall_gap(unit, cands[i]).abs > NEAR_WALL_MM.mm } || order.first
          return [cands[n], n]
        end

        n = cands.each_with_index.min_by { |c, _| c[:t] }[1]
        [cands[n], n]
      end

      # المسافة بين ضهر الوحدة (لو اتلفت ناحية الحيط) ومستوى الحيط
      def self.wall_gap(unit, cand)
        bg = [-cand[:normal][0], -cand[:normal][1]]
        back_most = FP.real_world_corners(unit).map { |p| p.x * bg[0] + p.y * bg[1] }.max
        cand[:plane_c] - back_most
      end

      def self.flush_with?(unit, cand, tol = 1.mm, min_dot = 0.9995)
        fx, fy = FP.front_dir(unit)
        return false if (fx * cand[:normal][0] + fy * cand[:normal][1]) < min_dot
        (wall_gap(unit, cand) - WALL_CLEARANCE_MM.mm).abs < tol
      end

      # نفس الوضع تقريباً (اللف + X,Y) — من غير ما الارتفاع أو فروق الأرقام الصغيرة تبوّظ المقارنة
      def self.same_pose?(a, b)
        return false unless a && b && a.size == b.size
        rot = [0, 1, 2, 4, 5, 6, 8, 9, 10]
        return false unless rot.all? { |i| (a[i] - b[i]).abs < 1e-3 }
        (a[12] - b[12]).abs < 0.12 && (a[13] - b[13]).abs < 0.12
      end

      def self.align_unit_to_wall(model, unit, hit, walls = nil)
        n = hit[:normal]
        back_goal = [-n[0], -n[1]]
        fx, fy = FP.front_dir(unit)
        back_now = [-fx, -fy]

        ang = Math.atan2(back_goal[1], back_goal[0]) - Math.atan2(back_now[1], back_now[0])
        ang = normalize_angle(ang)
        if ang.abs > 0.0005
          c = FP.world_center(unit)
          model.entities.transform_entities(Geom::Transformation.rotation(c, Z_AXIS, ang), [unit])
        end

        pts = FP.real_world_corners(unit)
        back_most = pts.map { |p| p.x * back_goal[0] + p.y * back_goal[1] }.max
        gap = hit[:plane_c] - back_most - WALL_CLEARANCE_MM.mm
        move = Geom::Vector3d.new(back_goal[0] * gap, back_goal[1] * gap, 0)
        model.entities.transform_entities(Geom::Transformation.translation(move), [unit]) if move.length > 0.01.mm

        fix = walls ? surface_penetration(unit, back_goal, walls) : 0.0
        if fix > 0.01.mm
          back_vec = Geom::Vector3d.new(-back_goal[0] * fix, -back_goal[1] * fix, 0)
          model.entities.transform_entities(Geom::Transformation.translation(back_vec), [unit])
        end
        side_fix = walls ? push_out_of_walls(model, unit, walls) : 0.0
        puts format('[UnitArranger] wall align: gap=%.2fmm  surface_fix=%.2fmm  side_fix=%.2fmm',
                    gap.to_mm, fix.to_mm, side_fix.to_mm)
      end

      def self.push_out_of_walls(model, unit, walls)
        return 0.0 if walls.nil? || walls.empty?
        total = 0.0
        2.times do
          changed = false
          fx, fy = FP.front_dir(unit)
          [[-fx, -fy], [-fy, fx], [fy, -fx]].each do |d|
            pen = direction_penetration(unit, d, walls)
            next if pen <= 0.01.mm
            vec = Geom::Vector3d.new(-d[0] * pen, -d[1] * pen, 0)
            model.entities.transform_entities(Geom::Transformation.translation(vec), [unit])
            total += pen
            changed = true
          end
          break unless changed
        end
        total
      end

      def self.direction_penetration(unit, d, walls)
        pts = FP.real_world_corners(unit)
        h   = FP.body_height_mm(unit).mm
        z0  = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
        direction_penetration_pts(pts, z0, h, d, walls)
      end

      def self.surface_penetration(unit, back_goal, walls)
        pts = FP.real_world_corners(unit)
        s_of = ->(p) { p.x * back_goal[0] + p.y * back_goal[1] }
        s_back = pts.map { |p| s_of.call(p) }.max
        max_fix = SURFACE_FIX_MAX_MM.mm

        par = [-back_goal[1], back_goal[0]]
        ps  = pts.map { |p| p.x * par[0] + p.y * par[1] }
        p_min, p_max = ps.min, ps.max

        h  = FP.body_height_mm(unit).mm
        z0 = (unit.transformation * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
        zs = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]
        fracs = [0.1, 0.3, 0.5, 0.7, 0.9]

        facing = walls.select { |w| (w[:n][0] * back_goal[0] + w[:n][1] * back_goal[1]) < -0.5 }
        return 0.0 if facing.empty?

        origin_s = s_back - max_fix - 10.mm
        worst = 0.0
        fracs.each do |f|
          pp = p_min + (p_max - p_min) * f
          ox = back_goal[0] * origin_s + par[0] * pp
          oy = back_goal[1] * origin_s + par[1] * pp
          zs.each do |z|
            o = Geom::Point3d.new(ox, oy, z)
            best = nil
            facing.each do |w|
              t = ray_hit(o, back_goal, w)
              best = t if t && (best.nil? || t < best)
            end
            next unless best
            s_hit = origin_s + best
            delta = s_back - s_hit
            next if delta <= 1.mm || delta > max_fix
            worst = delta if delta > worst
          end
        end
        worst > 0 ? worst + WALL_CLEARANCE_MM.mm : 0.0
      end

      def self.wall_candidates(unit, walls)
        c  = FP.world_center(unit)
        tr = unit.transformation
        h  = FP.body_height_mm(unit).mm
        z0 = (tr * Geom::Point3d.new(0, 0, 0)).z + FP::C::PLINTH_HEIGHT.mm
        heights = [z0 + h * 0.3, z0 + h * 0.6, z0 + h * 0.9]
        max_t = MAX_WALL_DISTANCE_MM.mm
        rc = FP.real_world_corners(unit)

        found = {}
        walls.each do |w|
          n = w[:n]
          side = n[0] * c.x + n[1] * c.y - w[:c]
          t = side.abs
          next if t < 1e-6 || t > max_t
          nf  = side > 0 ? n : [-n[0], -n[1]]
          off = side > 0 ? w[:c] : -w[:c]
          d   = [-nf[0], -nf[1]]

          par = [-d[1], d[0]]
          ps  = rc.map { |p| p.x * par[0] + p.y * par[1] }
          span = ps.max - ps.min
          origin = nil
          z_hit  = nil
          [0.0, -0.3, 0.3].each do |k|
            oc = Geom::Point3d.new(c.x + par[0] * span * k, c.y + par[1] * span * k, 0)
            zf = heights.find { |z| ray_hit(Geom::Point3d.new(oc.x, oc.y, z), d, w) }
            next unless zf
            origin = oc
            z_hit  = zf
            break
          end
          next unless z_hit

          ang = (Math.atan2(nf[1], nf[0]).radians % 360).round(1)
          key = [ang, (off.to_mm / 5.0).round]
          next if found[key] && found[key][:t] <= t
          found[key] = { key: key, normal: nf, plane_c: -off, t: t, ang: ang, off: off, z: z_hit, origin: origin }
        end

        list = found.values
        list.reject! do |cand|
          d = [-cand[:normal][0], -cand[:normal][1]]
          o = Geom::Point3d.new(cand[:origin].x, cand[:origin].y, cand[:z])
          walls.any? do |w2|
            next false if (w2[:n][0] * cand[:normal][0] + w2[:n][1] * cand[:normal][1]).abs > 0.9995 &&
                          ((w2[:n][0] * cand[:normal][0] + w2[:n][1] * cand[:normal][1]) > 0 ? w2[:c] : -w2[:c]) - cand[:off] > -2.mm &&
                          ((w2[:n][0] * cand[:normal][0] + w2[:n][1] * cand[:normal][1]) > 0 ? w2[:c] : -w2[:c]) - cand[:off] < 2.mm
            t2 = ray_hit(o, d, w2)
            t2 && t2 < cand[:t] - 2.mm
          end
        end
        list.sort_by { |cd| [cd[:ang], cd[:off]] }
      end

      def self.ray_hit(o, d, w)
        n = w[:n]
        denom = n[0] * d[0] + n[1] * d[1]
        return nil if denom.abs < 1e-6
        t = (w[:c] - (n[0] * o.x + n[1] * o.y)) / denom
        return nil if t <= 0
        p = Geom::Point3d.new(o.x + d[0] * t, o.y + d[1] * t, o.z)
        return nil if p.z < w[:zmin] - 1.mm || p.z > w[:zmax] + 1.mm
        lp = w[:inv] * p
        res = w[:face].classify_point(lp)
        inside = [Sketchup::Face::PointInside, Sketchup::Face::PointOnFace,
                  Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
        inside.include?(res) ? t : nil
      rescue StandardError
        nil
      end

      def self.collect_wall_faces(model)
        out = []
        walk = lambda do |entities, tr|
          entities.each do |e|
            next if e.respond_to?(:hidden?) && e.hidden?
            next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
            case e
            when Sketchup::Face
              next if e.area < MIN_WALL_FACE_AREA
              n = tr * e.normal
              len = Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
              next if len < 1e-9
              nx, ny, nz = n.x / len, n.y / len, n.z / len
              next if nz.abs > 0.1
              hl = Math.sqrt(nx * nx + ny * ny)
              nx, ny = nx / hl, ny / hl
              p0 = tr * e.vertices.first.position
              zs = e.vertices.map { |vtx| (tr * vtx.position).z }
              out << { face: e, n: [nx, ny], c: nx * p0.x + ny * p0.y,
                       inv: tr.inverse, zmin: zs.min, zmax: zs.max }
            when Sketchup::Group
              next if cabinet_neo_entity?(e)
              walk.call(e.entities, tr * e.transformation)
            when Sketchup::ComponentInstance
              next if cabinet_neo_entity?(e)
              walk.call(e.definition.entities, tr * e.transformation)
            end
          end
        end
        walk.call(model.entities, Geom::Transformation.new)
        out
      end

      def self.cabinet_neo_entity?(e)
        return true if e.get_attribute('CabinetNeo', 'generated', false)
        e.is_a?(Sketchup::ComponentInstance) &&
          e.definition.get_attribute('CabinetNeo', 'generated', false)
      rescue StandardError
        false
      end

      # =====================================================================
      # أداة «جنب وحدة تانية»
      # =====================================================================
      class BesideTool
        FP = UnitFootprint
        HILITE = Sketchup::Color.new(30, 190, 120, 90)
        EDGE   = Sketchup::Color.new(20, 160, 90)
        GHOST  = Sketchup::Color.new(255, 140, 0)

        def initialize(unit)
          @unit   = unit
          @target = nil
          @side   = nil
          @flip   = false
          @plan   = nil
        end

        def activate
          @model = Sketchup.active_model
          @ip    = Sketchup::InputPoint.new
          reset_hint
          @model.active_view.invalidate
        end

        def deactivate(view)
          view.invalidate
          if defined?(::CabinetNeo::UI::FloatingToolbar)
            ::CabinetNeo::UI::FloatingToolbar.resume_after_tool
          end
        end

        def resume(view)
          reset_hint
          view.invalidate
        end

        def onSetCursor
          ::UI.set_cursor(632)
        rescue StandardError
          nil
        end

        def onCancel(_reason, _view)
          Sketchup.active_model.select_tool(nil)
        end

        def onKeyDown(key, _repeat, _flags, _view)
          Sketchup.active_model.select_tool(nil) if key == 27
        end

        FLIP_MASK = (defined?(::CONSTRAIN_MODIFIER_MASK) ? ::CONSTRAIN_MODIFIER_MASK : 1) |
                    (defined?(::COPY_MODIFIER_MASK) ? ::COPY_MODIFIER_MASK : 2)

        def onMouseMove(flags, x, y, view)
          @flip = (flags.to_i & FLIP_MASK) != 0
          update_target(x, y, view)
          view.invalidate
        end

        def onLButtonDown(flags, x, y, view)
          @flip = (flags.to_i & FLIP_MASK) != 0
          update_target(x, y, view)
          unless @target && @side
            Sketchup.status_text = 'مفيش وحدة تحت المؤشر'
            return
          end
          res = UnitArranger.align_beside(@unit, @target, @side)
          if res[:success]
            Sketchup.status_text = "✅ #{res[:message]}"
            @model.selection.clear
            @model.selection.add(@unit) if @unit.valid?
            @model.select_tool(nil)
          else
            ::UI.messagebox("⚠️ #{res[:message]}", ::MB_OK, 'Cabinet Neo')
          end
        end

        def draw(view)
          return unless @target && @target.valid? && @side
          rb = FP.real_local_bounds(@target)
          if rb
            x0, y0, x1, y1, z0, z1 = rb
            tr = @target.transformation
            quad =
              if corner?(@target)
                _w1, d1, _w2, d2 = FP.corner_dims_mm(@target).map(&:mm)
                if @side == :arm2_end
                  [[x0, y1, z0], [x0 + d2, y1, z0], [x0 + d2, y1, z1], [x0, y1, z1]]
                else
                  [[x1, y0, z0], [x1, y0 + d1, z0], [x1, y0 + d1, z1], [x1, y0, z1]]
                end
              else
                xs = @side == :max_x ? x1 : x0
                [[xs, y0, z0], [xs, y1, z0], [xs, y1, z1], [xs, y0, z1]]
              end
            quad = quad.map { |x, y, z| tr * Geom::Point3d.new(x, y, z) }
            view.drawing_color = HILITE
            view.draw(GL_QUADS, quad)
            view.drawing_color = EDGE
            view.line_width = 3
            view.draw(GL_LINE_LOOP, quad)
          end
          if @plan
            view.drawing_color = GHOST
            view.line_width = 2
            view.draw(GL_LINE_LOOP, @plan[:footprint])
          end
        rescue StandardError => e
          puts "[BesideTool] draw: #{e.message}"
        end

        private

        def reset_hint
          Sketchup.status_text = 'اختار الوحدة اللي عايز تلزق جنبها (Shift/Ctrl = الجنب التاني — Esc للإلغاء)'
        end

        def pick_target(x, y, view)
          ph = view.pick_helper
          ph.do_pick(x, y)
          ph.count.times do |i|
            path = ph.path_at(i) || []
            ent = path.find do |e|
              (FP.cabinet_unit?(e) || CountertopBuilder.legacy_unit?(e)) && !e.equal?(@unit)
            end
            next unless ent
            return [ent, ph, i]
          end
          nil
        rescue StandardError
          nil
        end

        def update_target(x, y, view)
          hit = pick_target(x, y, view)
          unless hit
            @target = @side = @plan = nil
            reset_hint
            return
          end
          ent, ph, i = hit
          @target = ent
          @auto_side = detect_side(ent, ph, i, x, y, view)
          @side = @flip ? other_side(ent, @auto_side) : @auto_side
          refresh_plan
          Sketchup.status_text = "هتلزق جنب وحدة #{UnitArranger.unit_no(@target)} — اضغط للتأكيد (Shift/Ctrl = الجنب التاني)"
        end

        def refresh_plan
          return unless @target && @target.valid? && @side
          @side = (@flip ? other_side(@target, @auto_side) : @auto_side) if @auto_side
          @plan = UnitArranger.plan_beside(@unit, @target, @side)
        rescue StandardError => e
          puts "[BesideTool] plan: #{e.message}"
          @plan = nil
        end

        def corner?(ent)
          FP.subtype(ent) == 'corner_L'
        end

        def other_side(ent, side)
          if corner?(ent)
            side == :max_x ? :arm2_end : :max_x
          else
            side == :max_x ? :min_x : :max_x
          end
        end

        def detect_side(target, ph, idx, x, y, view)
          tr = target.transformation
          ux = tr.xaxis
          uy = tr.yaxis
          cor = corner?(target)
          leaf = ph.leaf_at(idx)
          if leaf.is_a?(Sketchup::Face)
            n = ph.transformation_at(idx) * leaf.normal
            d = n.dot(ux) / (n.length * ux.length)
            return :max_x if d > 0.9
            if cor
              dy = n.dot(uy) / (n.length * uy.length)
              return :arm2_end if dy > 0.9
            else
              return :min_x if d < -0.9
            end
          end
          @ip.pick(view, x, y)
          pos = @ip.position
          local = tr.inverse * pos
          if cor
            w1, _d1, w2, _d2 = FP.corner_dims_mm(target).map(&:mm)
            return (local.y / w2) > (local.x / w1) ? :arm2_end : :max_x
          end
          rb = FP.real_local_bounds(target)
          x0, x1 = rb ? [rb[0], rb[2]] : [FP.local_bounds(target)[0], FP.local_bounds(target)[2]]
          local.x >= (x0 + x1) / 2.0 ? :max_x : :min_x
        rescue StandardError
          :max_x
        end
      end
    end
  end
end