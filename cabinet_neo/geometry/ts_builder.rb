# encoding: UTF-8
# =============================================================================
# دولاب التخزين الطويل (tall_storage) — v3
# - وش بدون فتحات: درفة / درفتين فوق بعض / درفة سفلية + قلاب (بيفتح لفوق)
# - أدراج سفلية بعدد متحكم فيه (0..4) تحت أي تكوين
# - مقابض البلجن نفسها على الأدراج السفلية بس: L للدرج الأعلى، C لباقي الأدراج
# - الرفوف: عدد + فراغ سفلي + مواضع يدوي (مم من الأرض بما فيها الرجل)
# - v3: السقفية تستخدم :top + صناديق الأدراج تستخدم :drawer_box
# =============================================================================

module CabinetNeo
  module Geometry
    module CabinetBuilder
      TS_LAYOUTS = %w[door two_doors door_flip].freeze

      def self.ts_truthy(v)
        case v
        when true, 'true', '1', 1 then true
        else false
        end
      end

      def self.ts_normalize(raw)
        raw = (JSON.parse(raw) rescue {}) if raw.is_a?(String)
        raw = {} unless raw.is_a?(Hash)
        g = lambda do |k, dflt|
          v = raw.key?(k) ? raw[k] : raw[k.to_s]
          v.nil? ? dflt : v
        end

        layout  = g.call(:layout, 'door').to_s
        drawers = g.call(:drawer_n, 0).to_i
        if layout == 'drawer_door'
          layout  = 'door'
          drawers = 1 if drawers < 1
        end
        layout = 'door' unless TS_LAYOUTS.include?(layout)

        pos = g.call(:shelf_pos, [])
        pos = [] unless pos.is_a?(Array)
        pos = pos.map { |x| x.to_f }.select { |x| x > 0 }.sort

        {
          layout:    layout,
          handles:   ts_truthy(g.call(:handles, false)),
          drawer_n:  [[drawers, 0].max, 4].min,
          drawer_h:  [g.call(:drawer_h, 250.0).to_f, 100.0].max,
          split_h:   g.call(:split_h, layout == 'door_flip' ? 1700.0 : 1200.0).to_f,
          shelves:   [[g.call(:shelves, 4).to_i, 0].max, 12].min,
          clear_h:   [g.call(:clear_h, 0.0).to_f, 0.0].max,
          shelf_pos: pos
        }
      end

      def self.add_flip_door(ents, x, y, z_top, fw, fh, td, name, material, edge_config, mats)
        model = Sketchup.active_model
        PanelFactory.force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)
        definition.set_attribute('CabinetNeo', 'is_flip', true)
        definition.set_attribute('CabinetNeo', 'is_flip_up', true)
        definition.set_attribute('CabinetNeo', 'flip_open_angle', 90.0)

        pts = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(fw, 0, 0),
               Geom::Point3d.new(fw, td, 0), Geom::Point3d.new(0, td, 0)]
        face = definition.entities.add_face(pts)
        return nil unless face
        face.reverse! if face.normal.z < 0
        face.pushpull(-fh)

        if material
          definition.entities.grep(Sketchup::Face).each do |f|
            f.material = material
            f.back_material = material
          end
        end
        if edge_config && mats && !edge_config.empty?
          PanelFactory.apply_edge_banding_by_config(definition, edge_config, mats)
        end

        inst = ents.add_instance(definition, Geom::Transformation.new(Geom::Point3d.new(x, y, z_top)))
        inst.name = name
        inst
      end

      def self.ts_add_doors(ents, w, d, z_bot, z_top, door_type, tag, unit_ar,
                            door_mat, edge_cfg, mats, handles)
        td = C::DOOR_THICKNESS.mm
        gs = C::DOOR_GAP_SIDE.mm
        gm = C::DOOR_GAP_MIDDLE.mm
        dh = z_top - z_bot
        return if dh <= 20.0.mm

        made = []
        case door_type.to_s
        when 'single_right'
          made << add_hinged_door(ents, gs, d, z_bot, w - 2 * gs, td, dh, :plus_x,
                    "درفة #{tag} وحدة #{unit_ar}", door_mat, edge_cfg, mats)
        when 'single_left'
          made << add_hinged_door(ents, w - gs, d, z_bot, w - 2 * gs, td, dh, :minus_x,
                    "درفة #{tag} وحدة #{unit_ar}", door_mat, edge_cfg, mats)
        else
          dw = (w - 2 * gs - gm) / 2.0
          made << add_hinged_door(ents, gs, d, z_bot, dw, td, dh, :plus_x,
                    "درفة يمين #{tag} وحدة #{unit_ar}", door_mat, edge_cfg, mats)
          made << add_hinged_door(ents, w - gs, d, z_bot, dw, td, dh, :minus_x,
                    "درفة شمال #{tag} وحدة #{unit_ar}", door_mat, edge_cfg, mats)
        end
        made.compact.each do |inst|
          next unless inst.valid?
          inst.set_attribute('CabinetNeo', 'is_touch', true) unless handles
        end
      end

      def self.build_tall_storage_unit(ents, w, h, d, mats, unit_ar, custom_edges = nil,
                                       params = {}, door_type = 'double')
        model = Sketchup.active_model
        ts    = ts_normalize(params[:ts])

        t   = C::SIDE_THICKNESS.mm
        tb  = C::BACK_THICKNESS.mm
        tsh = C::SHELF_THICKNESS.mm
        bg  = C::BACK_GROOVE.mm
        br  = C::BACK_RECESS.mm
        td  = C::DOOR_THICKNESS.mm
        gs  = C::DOOR_GAP_SIDE.mm
        nh_h = C::HANDLE_NOTCH_HEIGHT.mm

        z0  = C::PLINTH_HEIGHT.mm
        z_t = z0 + h
        iw  = w - 2 * t

        handles  = ts[:handles]
        layout   = ts[:layout]
        small_gap = 2.0.mm
        big_gap   = 30.0.mm
        top_gap   = 2.0.mm

        door_mat = mats[:door_lac] || mats[:carcass]
        edge_cfg = resolve_edge_config(:door, custom_edges)
        drw_edge = resolve_edge_config(:drawer, custom_edges)
        box_edge = resolve_edge_config(:drawer_box, custom_edges)
        back_edge = resolve_edge_config(:drawer_back, custom_edges)

        n_dr  = ts[:drawer_n]
        dr_h  = ts[:drawer_h].mm
        max_zone = h - 450.0.mm
        dr_h  = max_zone / n_dr.to_f if n_dr > 0 && dr_h * n_dr > max_zone
        zone_top = z0 + dr_h * n_dr

        bounds = [z0]
        (1..n_dr).each { |i| bounds << z0 + dr_h * i }
        if layout != 'door'
          split = ts[:split_h].mm
          split = [[split, zone_top + 300.0.mm].max, z_t - 250.0.mm].min
          bounds << split
        end
        bounds << z_t

        kinds = []
        n_dr.times { kinds << :drawer }
        case layout
        when 'two_doors' then kinds += [:door, :door]
        when 'door_flip' then kinds += [:door, :flip]
        else                  kinds << :door
        end

        gap_above = lambda { |i| (handles && kinds[i] == :drawer) ? big_gap : small_gap }
        faces = []
        kinds.each_with_index do |k, i|
          last = (i == kinds.size - 1)
          fb = bounds[i] + (i > 0 ? gap_above.call(i - 1) / 2.0 : 0.0)
          ft = bounds[i + 1] - (last ? top_gap : gap_above.call(i) / 2.0)
          faces << { kind: k, bot: fb, top: ft, last: last,
                     top_drawer: (k == :drawer && i == n_dr - 1) }
        end

        notch_y = (d.to_mm - C::HANDLE_NOTCH_DEPTH).mm
        notches = []
        if handles
          faces.each do |f|
            next unless f[:kind] == :drawer
            nb = [f[:top] - 25.0.mm, z0 + t].max
            nt = [f[:top] - 25.0.mm + nh_h, z_t].min
            notches << { bot: nb, top: nt, depth_y: notch_y } if nb < nt - 1.mm
          end
        end

        # ═══ 1. الرجول + الهيكل ═══
        build_legs_and_plinth(ents, w, h, d, mats, unit_ar)
        PanelFactory.component_box(ents, 0, 0, z0, w, t, d,
          name: "أرضية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:floor, custom_edges), mats: mats)
        build_side_with_notches(ents, 0, d, t, z0, z_t, notches,
          name: "ج.شمال وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges), mats: mats)
        build_side_with_notches(ents, w - t, d, t, z0, z_t, notches,
          name: "ج.يمين وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:side, custom_edges), mats: mats)
        # ⭐ السقفية تستخدم :top (v3)
        PanelFactory.component_box(ents, t, 0, z_t - t, iw, t, d,
          name: "سقفية وحدة #{unit_ar}", material: mats[:carcass],
          edge_config: resolve_edge_config(:top, custom_edges), mats: mats)
        PanelFactory.component_box(ents, t - bg, br, z0 + t,
          iw + 2 * bg, (z_t - t) - (z0 + t), tb,
          name: "ضهرية وحدة #{unit_ar}", material: mats[:back],
          edge_config: {}, mats: mats)

        # ═══ 2. الأوجه + المقابض ═══
        drawer_i = 0
        faces.each do |f|
          fh = f[:top] - f[:bot]
          next if fh <= 20.0.mm

          case f[:kind]
          when :drawer
            drawer_i += 1
            front = PanelFactory.component_box(ents, gs, d, f[:bot], w - 2 * gs, fh, td,
              name: "واجهة درج #{drawer_i} وحدة #{unit_ar}", material: door_mat,
              edge_config: drw_edge, mats: mats)
            if front && front.valid?
              front.set_attribute('CabinetNeo', 'is_drawer', true)
              front.set_attribute('CabinetNeo', 'drawer_index', drawer_i)
              front.set_attribute('CabinetNeo', 'is_touch', true) unless handles
              tag_drawer_part(front, d)
            end
            # ⭐ تمرير custom_edges لـ build_drawer_box (v3)
            build_drawer_box(ents, w, d, t, f[:bot], fh, mats, unit_ar, drawer_i,
                             bottom_off: 20.0.mm, top_off: (handles ? 40.0.mm : 25.0.mm),
                             custom_edges: custom_edges)
          when :door
            ts_add_doors(ents, w, d, f[:bot], f[:top], door_type,
                         (f[:last] ? 'علوية' : 'سفلية'), unit_ar,
                         door_mat, edge_cfg, mats, false)
          when :flip
            inst = add_flip_door(ents, gs, d, f[:top], w - 2 * gs, fh, td,
                                 "درفة علوية قلاب وحدة #{unit_ar}", door_mat, edge_cfg, mats)
            inst.set_attribute('CabinetNeo', 'is_touch', true) if inst && inst.valid?
          end

          if handles && f[:kind] == :drawer
            if f[:top_drawer]
              build_handle_L_for_drawer(ents, w, fh, d, f[:bot], mats, unit_ar, drawer_i)
            else
              build_handle_C_for_drawer(ents, w, fh, d, f[:bot], mats, unit_ar, drawer_i)
            end
          end
        end

        # ═══ 3. الرفوف الداخلية ═══
        ts_build_shelves(ents, w, d, z0, z_t, t, tsh, br, tb, ts,
                         (n_dr > 0 ? zone_top : nil), mats, unit_ar, custom_edges)

        puts "[Cabinet Neo] 🗄️ دولاب تخزين #{unit_ar} اتبنى (#{layout}, drawers=#{n_dr}, handles=#{handles})"
      rescue StandardError => e
        puts "[Cabinet Neo] build_tall_storage_unit: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end

      def self.ts_build_shelves(ents, w, d, z0, z_t, t, tsh, br, tb, ts, drawer_top,
                                mats, unit_ar, custom_edges)
        iw      = w - 2 * t
        shelf_y = br + tb
        shelf_d = d - shelf_y
        return if shelf_d <= 0

        in_bot = z0 + t
        in_top = z_t - t
        zs = []

        if ts[:shelf_pos].is_a?(Array) && !ts[:shelf_pos].empty?
          zs = ts[:shelf_pos].map { |p| p.mm }
        elsif ts[:shelves] > 0
          lo = in_bot
          lo = [lo, ts[:clear_h].mm].max if ts[:clear_h] > 0
          lo = [lo, drawer_top + 20.0.mm].max if drawer_top
          span = in_top - lo
          return if span <= tsh * 2
          n = ts[:shelves]
          if ts[:clear_h] > 0
            zs = (0...n).map { |i| lo + span * i / n.to_f }
          else
            zs = (1..n).map { |i| lo + span * i / (n + 1).to_f - tsh / 2.0 }
          end
        end

        count = 0
        zs.each do |z|
          next if z < in_bot + 10.0.mm
          next if z + tsh > in_top - 5.0.mm
          count += 1
          PanelFactory.component_box(ents, t, shelf_y, z, iw, tsh, shelf_d,
            name: "رف #{count} وحدة #{unit_ar}", material: mats[:carcass],
            edge_config: resolve_edge_config(:shelf, custom_edges), mats: mats)
        end
      end
    end
  end
end