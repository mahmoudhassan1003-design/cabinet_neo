# encoding: UTF-8
# =============================================================================
# محمّل الصور — v4 (لا يحذف مادة قيد الاستخدام)
# =============================================================================

require 'securerandom'

module CabinetNeo
  module Materials
    module TextureLoader

      def self.textures_dir
        File.expand_path(File.join(__dir__, '..', 'textures'))
      end

      def self.available_textures
        dir = textures_dir
        unless File.directory?(dir)
          puts "[TextureLoader] ⚠️  المجلد غير موجود: #{dir}"
          return []
        end

        Dir.glob(File.join(dir, '*'))
           .select { |f| File.file?(f) && f =~ /\.(jpg|jpeg|png|bmp)$/i }
           .map do |path|
             {
               name: File.basename(path, '.*'),
               path: path,
               ext:  File.extname(path).downcase
             }
           end
      end

      # =======================================================================
      # ⭐ إنشاء/جلب مادة من صورة — نسخة آمنة
      # =======================================================================
      def self.ensure_texture_material(model, mat_name, texture_file)
        # ⭐ 1) إذا المادة موجودة مع صورة → استخدمها كما هي
        existing = model.materials[mat_name]
        if existing && existing.texture
          puts "[TextureLoader] ♻️  استخدام مادة موجودة: #{mat_name}"
          return existing
        end

        # 2) ابحث عن الصورة
        path = find_texture_path(texture_file)
        unless path
          puts "[TextureLoader] ❌ لم تُعثر على الصورة: #{texture_file}"
          return nil
        end

        # 3) إن كانت موجودة بدون صورة، احذفها أولاً (آمن لأنها غير مستخدمة)
        if existing
          begin
            model.materials.remove(existing)
            puts "[TextureLoader] 🗑️  حذف مادة بلا صورة: #{mat_name}"
          rescue StandardError => e
            puts "[TextureLoader] ⚠️  فشل حذف المادة: #{e.message}"
          end
        end

        # 4) أنشئ مادة جديدة
        mat = model.materials.add(mat_name)
        begin
          mat.texture = path
          puts "[TextureLoader] ✅ تم تحميل صورة: #{File.basename(path)} → #{mat_name}"
        rescue StandardError => e
          puts "[TextureLoader] ❌ فشل تحميل الصورة: #{e.message}"
          return nil
        end

        # 5) وسم OCL
        tag_as_board(mat, 18.0)
        mat
      rescue StandardError => e
        puts "[TextureLoader] ❌ خطأ: #{e.message}"
        nil
      end

      def self.find_texture_path(texture_file)
        if texture_file.to_s =~ /\.(jpg|jpeg|png|bmp)$/i
          direct = File.join(textures_dir, texture_file)
          return direct if File.exist?(direct)
        end

        found = available_textures.find { |t| t[:name] == texture_file.to_s }
        return found[:path] if found

        %w[.jpg .jpeg .png .bmp].each do |ext|
          candidate = File.join(textures_dir, "#{texture_file}#{ext}")
          return candidate if File.exist?(candidate)
        end

        nil
      end

      # =======================================================================
      # مادة بلون سادة — نسخة آمنة
      # =======================================================================
      def self.ensure_solid_material(model, mat_name, hex_color)
        new_color = parse_hex_color(hex_color)

        # ⭐ إذا المادة موجودة بلون مطابق → استخدمها
        existing = model.materials[mat_name]
        if existing && !existing.texture
          if existing.color &&
             existing.color.red   == new_color.red &&
             existing.color.green == new_color.green &&
             existing.color.blue  == new_color.blue
            puts "[TextureLoader] ♻️  استخدام مادة سادة موجودة: #{mat_name}"
            return existing
          end

          # اللون مختلف → حدّثه (بدون حذف)
          existing.color = new_color
          puts "[TextureLoader] 🎨 تحديث لون مادة: #{mat_name} (#{hex_color})"
          return existing
        end

        # احذف القديمة إن كانت بدون لون صحيح
        if existing
          begin
            model.materials.remove(existing)
          rescue StandardError
          end
        end

        mat = model.materials.add(mat_name)
        mat.color = new_color
        tag_as_board(mat, 18.0)
        puts "[TextureLoader] 🎨 إنشاء مادة سادة: #{mat_name} (#{hex_color})"
        mat
      rescue StandardError => e
        puts "[TextureLoader] ensure_solid_material('#{mat_name}'): #{e.message}"
        nil
      end

      def self.parse_hex_color(hex)
        hex = hex.to_s.sub('#', '')
        r = hex[0..1].to_i(16)
        g = hex[2..3].to_i(16)
        b = hex[4..5].to_i(16)
        Sketchup::Color.new(r, g, b)
      rescue StandardError
        Sketchup::Color.new(200, 200, 200)
      end

      def self.tag_as_board(mat, thickness = 18.0)
        ladb = mat.attribute_dictionary('ladb_opencutlist', true)
        ladb['type'] = 2
        ladb['uuid'] ||= SecureRandom.uuid
        ladb['std_thickness'] = thickness.to_s
        ladb['std_thicknesses'] ||= '15 mm;18 mm;22 mm'
        ladb['std_sizes'] ||= '2800 mm x 2070 mm'
        ladb['std_sizes_values'] ||= '2800;2070'
        ladb['edge_decremented'] ||= false
        ladb['raw_estimated'] ||= true
        ladb['grained'] ||= false

        legacy = mat.attribute_dictionary('OpenCutList', true)
        legacy['type'] = 'panel'
        legacy['std_thickness'] = thickness.to_s
      rescue StandardError => e
        puts "[TextureLoader] tag_as_board failed: #{e.message}"
      end

      # =======================================================================
      # 🧹 حذف كل المواد بلا استخدام (تنظيف فقط)
      # =======================================================================
      def self.cleanup_unused_texture_materials(model)
        removed = 0
        model.materials.to_a.each do |mat|
          # تجاهل المواد التي لها صورة (قد تكون قيد الاستخدام)
          next if mat.texture
          # تجاهل المواد الأساسية
          next if mat.name =~ /كونتر|UV LAC|LUMBER|بورديوم|اكسسوار|مقبض|شريط|مفحار|HPL/
          begin
            model.materials.remove(mat)
            removed += 1
          rescue StandardError
          end
        end
        puts "[TextureLoader] 🧹 حذف #{removed} مادة" if removed > 0
        removed
      end

      def self.debug_dump
        puts '=' * 60
        puts "[TextureLoader] 📁 مجلد الصور: #{textures_dir}"
        puts "[TextureLoader]    موجود؟ #{File.directory?(textures_dir)}"
        textures = available_textures
        puts "[TextureLoader] 📸 الصور المتاحة (#{textures.size}):"
        textures.each { |t| puts "     • #{t[:name]} (#{t[:ext]})" }
        puts '=' * 60
      end
    end
  end
end