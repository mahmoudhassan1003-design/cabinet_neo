# encoding: UTF-8
# =============================================================================
# مكتبة المواد — v4 (مع الرخام)
# =============================================================================

require 'securerandom'

module CabinetNeo
  module Materials
    module MaterialLibrary
      TYPE_BOARD    = 2
      TYPE_EDGE     = 4
      TYPE_HARDWARE = 5

      def self.ensure_material(model, name, color, type_int, options = {})
        mat = model.materials[name]
        created = false

        unless mat
          mat = model.materials.add(name)
          mat.color = color
          created = true
        end

        ladb = mat.attribute_dictionary('ladb_opencutlist', true)
        ladb['type'] = type_int
        ladb['uuid'] ||= SecureRandom.uuid
        ladb['raw_estimated']           ||= true
        ladb['edge_decremented']        ||= false
        ladb['grained']                 ||= false
        ladb['length_increase']         ||= '0'
        ladb['thickness_increase']      ||= '0'
        ladb['width_increase']          ||= '0'
        ladb['multiplier_coefficient']  ||= 1.0
        ladb['description']             ||= ''
        ladb['url']                     ||= ''
        ladb['std_prices']              ||= '[{"val":"","dim":null}]'
        ladb['std_cut_prices']          ||= '[{"val":"","dim":null}]'
        ladb['std_volumic_masses']      ||= '[{"val":"","dim":null}]'
        ladb['std_lengths']             ||= ''
        ladb['std_widths']              ||= ''
        ladb['std_sections']            ||= ''
        ladb['thickness']               ||= '0'

        case type_int
        when TYPE_BOARD
          thick = options[:thickness] || 18
          ladb['std_thicknesses']  = options[:std_thicknesses] || '15 mm;18 mm;22 mm'
          ladb['std_sizes']        = options[:std_sizes] || '2800 mm x 2070 mm'
          ladb['std_sizes_values'] = options[:std_sizes_values] || '2800;2070'
          ladb['std_thickness']    = thick.to_s
        when TYPE_EDGE
          ladb['std_widths']      = options[:std_widths]      || '18mm'
          ladb['std_thicknesses'] = options[:std_thicknesses] || '1mm'
        end

        legacy = mat.attribute_dictionary('OpenCutList', true)
        legacy['type'] = case type_int
                         when TYPE_BOARD    then 'panel'
                         when TYPE_HARDWARE then 'hardware'
                         when TYPE_EDGE     then 'edge'
                         else                    'panel'
                         end

        tag = case type_int
              when TYPE_BOARD    then '📦 لوح'
              when TYPE_HARDWARE then '🔧 عتاد'
              when TYPE_EDGE     then '▤ حاشية'
              else                    '?'
              end
        puts "[Cabinet Neo] #{created ? '➕' : '✅'} #{name.ljust(30)} → #{tag}"
        mat
      rescue StandardError => e
        puts "[Cabinet Neo] ensure_material('#{name}'): #{e.message}"
        nil
      end

      # =======================================================================
      # تجهيز كل المواد
      # =======================================================================
      def self.prepare_defaults(model)
        c = Geometry::Constants

        {
          # --- مواد الأساس ---
          carcass:    ensure_material(model, c::MAT_CARCASS, c::COLOR_CARCASS,
                                       TYPE_BOARD, thickness: 18),
          door_lac:   ensure_material(model, c::MAT_DOOR_LAC, c::COLOR_DOOR_LAC,
                                       TYPE_BOARD, thickness: 18),
          door_wood:  ensure_material(model, c::MAT_DOOR_WOOD, c::COLOR_DOOR_WOOD,
                                       TYPE_BOARD, thickness: 18),
          back:       ensure_material(model, c::MAT_BACK, c::COLOR_BACK,
                                       TYPE_BOARD, thickness: 6),
          plinth:     ensure_material(model, c::MAT_PLINTH, c::COLOR_PLINTH,
                                       TYPE_HARDWARE),
          handle:     ensure_material(model, c::MAT_HANDLE, c::COLOR_HANDLE,
                                       TYPE_HARDWARE),

          # --- ⭐ الرخام ---
          countertop: ensure_material(model, c::MAT_COUNTERTOP, c::COLOR_COUNTERTOP,
                                       TYPE_BOARD, thickness: 40),

          # --- الحواشي ---
          edge_white: ensure_material(model, c::MAT_EDGE_WHITE, c::COLOR_EDGE_WHITE,
                                       TYPE_EDGE, std_widths: '18mm'),
          edge_plain: ensure_material(model, c::MAT_EDGE_PLAIN, c::COLOR_EDGE_PLAIN,
                                       TYPE_EDGE, std_widths: '18mm'),
          edge_dark:  ensure_material(model, c::MAT_EDGE_DARK, c::COLOR_EDGE_DARK,
                                       TYPE_EDGE, std_widths: '18mm'),

          edge_wood:  ensure_material(model, 'شريط خشبي',
                                       Sketchup::Color.new(160, 115, 70),
                                       TYPE_EDGE, std_widths: '18mm'),
          edge_grey:  ensure_material(model, 'شريط رمادي',
                                       Sketchup::Color.new(100, 100, 100),
                                       TYPE_EDGE, std_widths: '18mm'),

          # --- Matte Grey ---
          carcass_grey: ensure_material(model, 'كونتر رمادي',
                                         Sketchup::Color.new(150, 150, 150),
                                         TYPE_BOARD, thickness: 18),
          door_grey:    ensure_material(model, 'UV LAC رمادي 18',
                                         Sketchup::Color.new(130, 130, 130),
                                         TYPE_BOARD, thickness: 18)
        }.select { |_, v| v }
      end

      def self.migrate_old_materials(model)
        old_names = %w[
          CabinetNeo_Carcass CabinetNeo_Door CabinetNeo_Back
          CabinetNeo_Shelf CabinetNeo_Handle CabinetNeo_Plinth
        ]
        removed = 0
        old_names.each do |name|
          mat = model.materials[name]
          next unless mat
          begin
            model.materials.remove(mat)
            removed += 1
          rescue StandardError
          end
        end
        puts "[Cabinet Neo] 🧹 Removed #{removed} old material(s)"
        removed
      end
    end
  end
end