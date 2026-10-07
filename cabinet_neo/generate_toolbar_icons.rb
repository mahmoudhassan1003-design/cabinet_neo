# encoding: UTF-8
require 'zlib'
require 'fileutils'

ICONS_DIR = 'C:/Users/ot/AppData/Roaming/SketchUp/SketchUp 2026/SketchUp/Plugins/cabinet_neo/icons'

module CabinetNeoIconGen
  V_TOP     = [0.500, 0.094].freeze
  V_RIGHT   = [0.906, 0.313].freeze
  V_B_RIGHT = [0.906, 0.688].freeze
  V_BOTTOM  = [0.500, 0.906].freeze
  V_B_LEFT  = [0.094, 0.688].freeze
  V_LEFT    = [0.094, 0.313].freeze
  V_CENTER  = [0.500, 0.531].freeze

  COLOR_TOP   = [255, 179, 122].freeze
  COLOR_LEFT  = [255, 107,  26].freeze
  COLOR_RIGHT = [209,  77,   0].freeze

  def self.sample(nx, ny)
    return COLOR_TOP   if in_quad?(nx, ny, V_TOP,    V_RIGHT,  V_CENTER, V_LEFT)
    return COLOR_LEFT  if in_quad?(nx, ny, V_CENTER, V_LEFT,   V_B_LEFT, V_BOTTOM)
    return COLOR_RIGHT if in_quad?(nx, ny, V_CENTER, V_RIGHT,  V_B_RIGHT, V_BOTTOM)
    nil
  end

  def self.in_quad?(px, py, *verts)
    inside = false
    n = verts.size
    j = n - 1
    n.times do |i|
      xi, yi = verts[i]
      xj, yj = verts[j]
      if ((yi > py) != (yj > py)) && (px < (xj - xi) * (py - yi) / (yj - yi) + xi)
        inside = !inside
      end
      j = i
    end
    inside
  end

  def self.render(size, ss = 4)
    total = (ss * ss).to_f
    pixels = Array.new(size * size * 4, 0.0)
    size.times do |y|
      size.times do |x|
        r = g = b = 0.0
        covered = 0
        ss.times do |sy|
          ss.times do |sx|
            nx = (x + (sx + 0.5) / ss) / size.to_f
            ny = (y + (sy + 0.5) / ss) / size.to_f
            c = sample(nx, ny)
            if c
              r += c[0]; g += c[1]; b += c[2]
              covered += 1
            end
          end
        end
        i = (y * size + x) * 4
        if covered > 0
          pixels[i]     = r / covered
          pixels[i + 1] = g / covered
          pixels[i + 2] = b / covered
        end
        pixels[i + 3] = (covered / total) * 255.0
      end
    end
    pixels
  end

  def self.write_png(path, w, h, pixels)
    # ⭐ التصليح: كل قيمة تتحول لبايت واحد باستخدام 'C*'
    byte_values = pixels.map { |v| [[v.round, 0].max, 255].min }
    bytes = byte_values.pack('C*')

    row_size = w * 4
    filtered = String.new(encoding: 'BINARY')
    h.times do |y|
      filtered << "\x00".b
      filtered << bytes[y * row_size, row_size]
    end
    compressed = Zlib::Deflate.deflate(filtered)

    png = String.new(encoding: 'BINARY')
    png << "\x89PNG\r\n\x1a\n".b
    png << png_chunk('IHDR', [w, h, 8, 6, 0, 0, 0].pack('N2C5'))
    png << png_chunk('IDAT', compressed)
    png << png_chunk('IEND', '')
    File.binwrite(path, png)
  end

  def self.png_chunk(type, data)
    t = type.b
    d = data.to_s.b
    [d.bytesize].pack('N') + t + d + [Zlib.crc32(t + d)].pack('N')
  end

  def self.generate!(output_dir)
    FileUtils.mkdir_p(output_dir) rescue nil
    unless File.directory?(output_dir)
      puts "[IconGen] ❌ مش قادر أنشئ المجلد: #{output_dir}"
      return
    end
    [[16, 'cabinet_neo_16.png'], [24, 'cabinet_neo_24.png']].each do |size, name|
      pixels = render(size)
      path = File.join(output_dir, name).tr('\\', '/')
      write_png(path, size, size, pixels)
      puts "[IconGen] ✅ #{name} (#{size}×#{size})"
      puts "[IconGen]    → #{path}"
    end
    puts '[IconGen] 🎉 تم إنشاء الأيقونات بنجاح!'
  end
end

puts '=' * 60
puts "[IconGen] 📁 المسار: #{ICONS_DIR}"
puts '=' * 60
CabinetNeoIconGen.generate!(ICONS_DIR)
