# encoding: UTF-8
# =============================================================================
# مراعاة الأرض — v1
# =============================================================================
# - بيلاقي سطح الأرض اللي تحت الوحدة (أي وجه أفقي في الموديل، من غير عناصر
#   Cabinet Neo زي الرخامة والوحدات نفسها).
# - أداة النقل بتستخدمه عشان الوحدة تفضل واقفة على الأرض مهما كانت نقطة السنّاب.
# - مراقب اللصق: لو لصقت (Ctrl+V) أو عملت نسخة من وحدة، النسخة بتتنزّل على
#   الأرض تلقائي (الوحدات العلوية 'upper' بتتسيب زي ما هي).
#
# لو مفيش أرض مرسومة في الموديل → مفيش تغيير في الارتفاع.
# =============================================================================

module CabinetNeo
  module Geometry
    module FloorSnap
      FP = UnitFootprint

      TOL_ABOVE_MM  = 300.0     # أعلى وجه لحد 30 سم فوق قاعدة الوحدة (بسبب درجات/منصّات)
      MIN_FACE_AREA = 50.0      # بوصة مربعة — نتجاهل الأوجه الصغيرة
      MAX_FACES     = 30_000

      # ---------------------------------------------------------------------
      # أي وحدة بتقف على الأرض (كل حاجة غير العلوي)
      # ---------------------------------------------------------------------
      def self.ground_unit?(unit)
        FP.category(unit) != 'upper'
      rescue StandardError
        true
      end

      def self.base_z(unit)
        (unit.transformation * Geom::Point3d.new(0, 0, 0)).z
      end

      # ---------------------------------------------------------------------
      # جمع الأوجه الأفقية (مرة واحدة قبل الاستخدام)
      # ---------------------------------------------------------------------
      def self.collect_floor_faces(model)
        out = []
        walk = lambda do |entities, tr|
          entities.each do |e|
            break if out.size >= MAX_FACES
            next if e.respond_to?(:hidden?) && e.hidden?
            next if e.respond_to?(:layer) && e.layer && !e.layer.visible?
            case e
            when Sketchup::Face
              next if e.area < MIN_FACE_AREA
              n = tr * e.normal
              len = Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
              next if len < 1e-9 || (n.z / len).abs < 0.99
              pts = e.vertices.map { |v| tr * v.position }
              zs  = pts.map(&:z)
              next if (zs.max - zs.min) > 1.mm
              xs = pts.map(&:x); ys = pts.map(&:y)
              out << { face: e, z: zs.first, inv: tr.inverse,
                       x0: xs.min, x1: xs.max, y0: ys.min, y1: ys.max }
            when Sketchup::Group
              next if neo_entity?(e)
              walk.call(e.entities, tr * e.transformation)
            when Sketchup::ComponentInstance
              next if neo_entity?(e)
              walk.call(e.definition.entities, tr * e.transformation)
            end
          end
        end
        walk.call(model.entities, Geom::Transformation.new)
        out
      end

      def self.neo_entity?(e)
        return true if e.get_attribute('CabinetNeo', 'generated', false)
        e.is_a?(Sketchup::ComponentInstance) &&
          e.definition.get_attribute('CabinetNeo', 'generated', false)
      rescue StandardError
        false
      end

      # ---------------------------------------------------------------------
      # ارتفاع الأرض تحت النقطة (x,y) — أعلى وجه لحد ref_z + TOL
      # بيرجّع nil لو مفيش
      # ---------------------------------------------------------------------
      def self.floor_z_at(faces, x, y, ref_z)
        limit = ref_z + TOL_ABOVE_MM.mm
        best = nil
        inside = [Sketchup::Face::PointInside, Sketchup::Face::PointOnFace,
                  Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex]
        faces.each do |f|
          next if f[:z] > limit
          next if best && f[:z] <= best
          next if x < f[:x0] || x > f[:x1] || y < f[:y0] || y > f[:y1]
          lp = f[:inv] * Geom::Point3d.new(x, y, f[:z])
          best = f[:z] if inside.include?(f[:face].classify_point(lp))
        end
        best
      rescue StandardError
        nil
      end

      # الإزاحة الرأسية اللازمة عشان وحدة تقف على الأرض لو اتنقل مركزها لـ (cx, cy)
      def self.dz_for(unit, faces, cx, cy)
        base = base_z(unit)
        zf = floor_z_at(faces, cx, cy, base)
        zf ? (zf - base) : 0.0
      end

      # ---------------------------------------------------------------------
      # نزّل الوحدات على الأرض (بيشتغل جوه Operation من المنادي)
      # ---------------------------------------------------------------------
      def self.snap_units(model, units, faces)
        n = 0
        units.each do |u|
          next unless u.valid? && ground_unit?(u)
          c  = FP.world_center(u)
          dz = dz_for(u, faces, c.x, c.y)
          next if dz.abs < 0.5.mm
          model.entities.transform_entities(
            Geom::Transformation.translation(Geom::Vector3d.new(0, 0, dz)), [u]
          )
          n += 1
        end
        n
      end

      # ---------------------------------------------------------------------
      # مراقب اللصق / النسخ
      # ---------------------------------------------------------------------
      @pending = []
      @timer   = nil
      @busy    = false

      def self.note_added(entity)
        return if @busy
        return unless entity.is_a?(Sketchup::ComponentInstance) && entity.valid?
        return unless entity.definition.get_attribute('CabinetNeo', 'generated', false)
        @pending << entity
      rescue StandardError
      end

      def self.flush_later
        return if @pending.empty? || @timer
        @timer = ::UI.start_timer(0.15, false) do
          @timer = nil
          process_pending
        end
      rescue StandardError => e
        @timer = nil
        puts "[FloorSnap] flush_later: #{e.message}"
      end

      def self.process_pending
        list = @pending.select do |u|
          u.valid? && FP.cabinet_unit?(u) && u.definition.instances.size > 1 && ground_unit?(u)
        end
        @pending.clear
        return if list.empty?

        model = Sketchup.active_model
        faces = collect_floor_faces(model)
        return if faces.empty?

        @busy = true
        model.start_operation('Cabinet Neo: مراعاة الأرض', true, false, true)
        begin
          n = snap_units(model, list, faces)
          model.commit_operation
          puts "[FloorSnap] 🧱 نزّلت #{n} نسخة على الأرض" if n > 0
        rescue StandardError => e
          model.abort_operation
          puts "[FloorSnap] process_pending: #{e.message}"
        end
      ensure
        @busy = false
      end

      class EntitiesWatcher < Sketchup::EntitiesObserver
        def onElementAdded(_entities, entity)
          FloorSnap.note_added(entity)
        end
      end

      class CommitWatcher < Sketchup::ModelObserver
        def onTransactionCommit(_model)
          FloorSnap.flush_later
        end
      end

      def self.attach(model = Sketchup.active_model)
        return unless model
        detach
        @ents_obs  = EntitiesWatcher.new
        @model_obs = CommitWatcher.new
        @model_ref = model
        model.entities.add_observer(@ents_obs)
        model.add_observer(@model_obs)
        puts '[Cabinet Neo] 🧱 Floor observer registered'
      rescue StandardError => e
        puts "[Cabinet Neo] ❌ Floor observer failed: #{e.message}"
      end

      def self.detach
        return unless @model_ref
        begin; @model_ref.entities.remove_observer(@ents_obs) if @ents_obs; rescue StandardError; end
        begin; @model_ref.remove_observer(@model_obs) if @model_obs; rescue StandardError; end
        @ents_obs = @model_obs = @model_ref = nil
      end
    end
  end
end

puts '[Cabinet Neo] ✅ floor_snap.rb loaded'
