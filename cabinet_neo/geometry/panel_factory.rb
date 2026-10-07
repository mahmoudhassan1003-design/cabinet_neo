# encoding: UTF-8
# =============================================================================
# مصنع الألواح — v13 (تصحيح المحاور: sy على Z، sz على Y)
# =============================================================================

module CabinetNeo
  module Geometry
    module PanelFactory
      class << self
        attr_accessor :skip_purge
      end
      @skip_purge = false

      def self.force_delete_definitions(model, def_name)
        return 0 if @skip_purge
        deleted = 0
        model.definitions.to_a.each do |d|
          n = d.name.to_s
          is_match = (n == def_name) ||
                     n.start_with?("#{def_name}#") ||
                     n.start_with?("#{def_name} #")
          next unless is_match
          d.instances.to_a.each do |inst|
            begin
              p = inst.parent
              inst.erase! if p && p.valid?
            rescue StandardError
            end
          end
          begin
            d.erase! if d.valid?
            deleted += 1
          rescue StandardError
          end
        end
        deleted
      end

      # -----------------------------------------------------------------------
      # component_box — v13
      # -----------------------------------------------------------------------
      # الترتيب: sx → X (العرض)، sy → Z (الارتفاع)، sz → Y (العمق)
      # -----------------------------------------------------------------------
      def self.component_box(parent_entities, x, y, z, sx, sy, sz,
                              name: 'قطعة', material: nil,
                              edge_config: nil, mats: nil)
        return nil if sx <= 0 || sy <= 0 || sz <= 0

        if sx > 5000.mm || sy > 5000.mm || sz > 5000.mm
          puts "[PanelFactory] ⚠️ أبعاد مبالغ فيها: #{name} → sx=#{sx.to_mm.round(0)} sy=#{sy.to_mm.round(0)} sz=#{sz.to_mm.round(0)} مم"
          return nil
        end

        model = Sketchup.active_model
        force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)

        # ⭐ الرسم: sx على X، sz على Y
        pts = [
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(sx, 0, 0),
          Geom::Point3d.new(sx, sz, 0),   # ⭐ sz على Y
          Geom::Point3d.new(0, sz, 0)
        ]
        face = definition.entities.add_face(pts)
        return nil unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(sy)                  # ⭐ sy على Z

        apply_material_to_faces(definition, material) if material

        if edge_config && mats
          apply_edge_banding_by_config(definition, edge_config, mats)
        end

        transform = Geom::Transformation.new(Geom::Point3d.new(x, y, z))
        instance  = parent_entities.add_instance(definition, transform)
        instance.name = name
        instance
      end

      # -----------------------------------------------------------------------
      # component_L — لوح أفقي بشكل L كقطعة واحدة (Component زي باقي الألواح)
      #   ذراع 1: x=0..w1 / y=0..d1      ذراع 2: x=0..d2 / y=0..w2
      # -----------------------------------------------------------------------
      def self.component_L(parent_entities, x, y, z, w1, d1, w2, d2, t,
                           name: 'قطعة L', material: nil,
                           edge_config: nil, mats: nil)
        return nil if [w1, d1, w2, d2, t].any? { |v| v <= 0 }

        model = Sketchup.active_model
        force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)

        pts = [
          Geom::Point3d.new(0,  0,  0),
          Geom::Point3d.new(w1, 0,  0),
          Geom::Point3d.new(w1, d1, 0),
          Geom::Point3d.new(d2, d1, 0),
          Geom::Point3d.new(d2, w2, 0),
          Geom::Point3d.new(0,  w2, 0)
        ]
        face = definition.entities.add_face(pts)
        return nil unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(t)

        apply_material_to_faces(definition, material) if material
        apply_edge_banding_by_config(definition, edge_config, mats) if edge_config && mats

        instance = parent_entities.add_instance(definition,
                     Geom::Transformation.new(Geom::Point3d.new(x, y, z)))
        instance.name = name
        instance
      end

      # -----------------------------------------------------------------------
      # component_profile — بدون تغيير
      # -----------------------------------------------------------------------
      def self.component_profile(parent_entities, x, profile, thickness_x,
                                  name: 'قطعة', material: nil,
                                  edge_config: nil, mats: nil)
        return nil if thickness_x <= 0 || profile.size < 3

        if thickness_x > 5000.mm
          puts "[PanelFactory] ⚠️ سماكة مبالغ فيها: #{name} → #{thickness_x.to_mm.round(0)} مم"
          return nil
        end

        model = Sketchup.active_model
        force_delete_definitions(model, name)

        definition = model.definitions.add(name)
        definition.set_attribute('CabinetNeo', 'generated', true)
        definition.set_attribute('CabinetNeo', 'piece_name', name)

        pts = profile.map { |y, z| Geom::Point3d.new(0, y, z) }
        face = definition.entities.add_face(pts)
        return nil unless face

        face.reverse! if face.normal.x < 0
        face.pushpull(thickness_x)

        apply_material_to_faces(definition, material) if material

        if edge_config && mats
          apply_edge_banding_by_config(definition, edge_config, mats)
        end

        transform = Geom::Transformation.new(Geom::Point3d.new(x, 0, 0))
        instance  = parent_entities.add_instance(definition, transform)
        instance.name = name
        instance
      end

      def self.apply_material_to_faces(definition, material)
        definition.entities.grep(Sketchup::Face).each do |f|
          f.material      = material
          f.back_material = material
        end
      rescue StandardError => e
        puts "[Cabinet Neo] apply_material_to_faces failed: #{e.message}"
      end

      def self.apply_material_to_definition(definition, material)
        apply_material_to_faces(definition, material)
      end

      def self.apply_edge_banding_by_config(definition, edge_config, mats)
        return if edge_config.nil? || edge_config.empty?

        applied = 0

        definition.entities.grep(Sketchup::Face).each do |face|
          bb = face.bounds
          dims = [
            (bb.max.x - bb.min.x).to_mm.round(1),
            (bb.max.y - bb.min.y).to_mm.round(1),
            (bb.max.z - bb.min.z).to_mm.round(1)
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

          mat_key = edge_config[direction]
          next unless mat_key

          material = resolve_edge_material(mat_key, mats)
          next unless material

          face.material      = material
          face.back_material = material
          applied += 1
        end

        puts "  🎨 #{definition.name}: #{applied} حاشية" if applied > 0
      rescue StandardError => e
        puts "[Cabinet Neo] apply_edge_banding_by_config failed: #{e.message}"
      end

      def self.resolve_edge_material(key, mats)
        case key.to_s
        when 'white' then mats[:edge_white]
        when 'plain' then mats[:edge_plain]
        when 'dark'  then mats[:edge_dark] || mats[:edge_white]
        else nil
        end
      end
    end
  end
end