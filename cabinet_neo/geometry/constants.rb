# encoding: UTF-8
# =============================================================================
# ثوابت الهندسة + قواعد الحواشي + الأدراج + الأرجل (v29)
# (+ tall_oven + TALL_OVEN_BOTTOM_TYPES + :top config)
# =============================================================================

module CabinetNeo
  module Geometry
    module Constants
      SIDE_THICKNESS  = 18.0
      SHELF_THICKNESS = 18.0
      DOOR_THICKNESS  = 18.0
      SINK_THICKNESS  = 17.0
      SINK_MAT_NAME   = 'بورديوم'

      CORNER_W_RIGHT_DEFAULT = 900.0
      CORNER_W_LEFT_DEFAULT  = 900.0
      CORNER_D_RIGHT_DEFAULT = 580.0
      CORNER_D_LEFT_DEFAULT  = 580.0

      BACK_THICKNESS = 6.0
      BACK_RECESS    = 18.0
      BACK_GROOVE    = 7.0

      BACK_RAIL_THICKNESS = 18.0
      BACK_RAIL_HEIGHT    = 80.0
      TOP_RAIL_DEPTH      = 80.0
      FRONT_RAIL_RECESS   = 20.0

      HANDLE_NOTCH_DEPTH  = 20.0
      HANDLE_NOTCH_HEIGHT = 55.0

      DOOR_GAP_SIDE   = 1.0
      DOOR_GAP_MIDDLE = 2.0
      DOOR_GAP_TOP    = 30.0
      DOOR_GAP_BOTTOM = 0.0

      PLINTH_HEIGHT    = 100.0
      PLINTH_THICKNESS = 10.0
      PLINTH_RECESS    = 40.0

      DOUBLE_DOOR_THRESHOLD = 600.0

      DEFAULT_WIDTH  = 600.0
      DEFAULT_HEIGHT = 780.0
      DEFAULT_DEPTH  = 580.0

      MIN_WIDTH     = 200.0
      MIN_HEIGHT    = 300.0
      MIN_DEPTH     = 200.0
      MAX_DIMENSION = 3000.0

      COUNTERTOP_THICKNESS = 40.0
      COUNTERTOP_OVERHANG  = 40.0
      UPSTAND_HEIGHT       = 60.0
      UPSTAND_THICKNESS    = 20.0

      CROWN_HEIGHT    = 60.0
      CROWN_THICKNESS = 18.0
      CROWN_PROTRUDE  = 20.0

      CABINET_TYPES = {
        'lower'    => 'سفلي',
        'upper'    => 'علوي',
        'wardrobe' => 'دولاب',
        'balcony'  => 'بلكونة'
      }.freeze

      UNIT_SUBTYPES = {
        'standard'      => 'عادي (باب)',
        'drawers'       => 'أدراج',
        'oven'          => 'فرن',
        'corner_L'      => 'كورنر L',
        'sink'          => 'حوض',
        'counter_fixed' => 'سدة كونتر',
        'tall_oven'     => 'دولاب فرن',
        'tall_storage'  => 'دولاب تخزين'
      }.freeze

      TALL_OVEN_BOTTOM_TYPES = {
        'drawers' => 'درجين تحت',
        'door'    => 'درفة تحت',
        'double'  => 'درفتين تحت'
      }.freeze

      DRAWER_GAP             = 30.0
      DRAWER_BOX_THICKNESS   = 18.0
      DRAWER_BOTTOM_THICK    = 6.0
      DRAWER_BOTTOM_INSET    = 18.0
      DRAWER_BOX_FRONT_THICK = 18.0

      DRAWER_BOX_DEPTH       = 450.0
      DRAWER_BOX_DEPTH_MIN   = 300.0
      DRAWER_BOX_DEPTH_MAX   = 500.0

      DRAWER_BOX_DEPTHS_DEFAULT = [450.0, 450.0, 450.0]

      DRAWER_BOX_HEIGHT      = 150.0
      DRAWER_BOX_HEIGHT_MIN  = 80.0
      DRAWER_BOX_HEIGHT_MAX  = 250.0

      DRAWER_SIDE_CLEARANCE  = 0.0
      DRAWER_BACK_CLEARANCE  = 20.0
      DRAWER_FRONT_CLEAR     = 20.0
      DRAWER_TOP_CLEAR       = 60.0

      DRAWER_HEIGHTS_DEFAULT = [230.0, 230.0, 230.0]
      DRAWER_HEIGHT_MIN = 100.0
      DRAWER_HEIGHT_MAX = 400.0

      DRAWER_TOP_EDGE_HEIGHT = 3.0

      LEG_SIZE   = 40.0
      LEG_INSET  = 15.0
      LEG_HEIGHT = 100.0

      OVEN_WIDTH    = 600.0
      OVEN_HEIGHT   = 600.0
      OVEN_CLEAR    = 10.0
      OVEN_BOTTOM_Z = 200.0

      CORNER_SIZE_DEFAULT = 900.0
      CORNER_SIDE_BLIND   = 100.0

      MAT_CARCASS    = 'كونتر'.freeze
      MAT_DOOR_LAC   = 'UV LAC أبيض 18'.freeze
      MAT_DOOR_WOOD  = 'LUMBER J-Y114'.freeze
      MAT_BACK       = 'ظهور بورديوم 6مملي'.freeze
      MAT_PLINTH     = 'اكسسوار'.freeze
      MAT_HANDLE     = 'مقبض حرف L اسود'.freeze
      MAT_EDGE_WHITE = 'شريط ابيض مط1'.freeze
      MAT_EDGE_PLAIN = 'شريط سادة'.freeze
      MAT_EDGE_DARK  = 'مفحار1'.freeze
      MAT_COUNTERTOP = 'رخام'.freeze

      COLOR_CARCASS     = Sketchup::Color.new(194, 216, 255)
      COLOR_DOOR_LAC    = Sketchup::Color.new(250, 250, 248)
      COLOR_DOOR_WOOD   = Sketchup::Color.new(184, 178, 173)
      COLOR_BACK        = Sketchup::Color.new(96, 111, 107)
      COLOR_PLINTH      = Sketchup::Color.new(87, 175, 0)
      COLOR_HANDLE      = Sketchup::Color.new(10, 10, 10)
      COLOR_EDGE_WHITE  = Sketchup::Color.new(255, 255, 255)
      COLOR_EDGE_PLAIN  = Sketchup::Color.new(248, 181, 62)
      COLOR_EDGE_DARK   = Sketchup::Color.new(0, 0, 255)
      COLOR_COUNTERTOP  = Sketchup::Color.new(235, 235, 232)

      # ⭐ v29: إضافة :top للسقفية
      EDGE_FACES_DEFAULT = {
        floor:      { front: :white, back: :dark, left: :white, right: :white },
        side:       { front: :white, back: :dark, top: :white },
        top:        { front: :white, back: :dark, left: :white, right: :white },   # ⭐ سقفية
        shelf:      { front: :white },
        front_rail: { front: :white, back: :white },
        back_rail:  { top: :white },
        door:       { left: :plain, right: :plain, top: :plain, bottom: :plain },
        drawer:     { left: :plain, right: :plain, top: :plain, bottom: :plain },
        drawer_box: { top: :white },
        drawer_back:{ top: :white },
        crown:      { front: :white, left: :white, right: :white, top: :white },
        countertop: {},
        upstand:    {},
        back:       {},
        plinth:     {},
        handle:     {}
      }.freeze

      EDGE_FACES_LABELS = {
        floor:      'الأرضية',
        side:       'الجنبان',
        top:        'السقفية',    # ⭐ جديد
        shelf:      'الأرفف',
        front_rail: 'المداد الأمامي',
        back_rail:  'المداد الخلفي',
        door:       'الدرف',
        drawer:     'الأدراج',
        drawer_box: 'وش الصندوق',
        drawer_back:'ضهر الصندوق',
        crown:      'التاج',
        countertop: 'الرخامة',
        upstand:    'المراية',
        back:       'الضهرية',
        plinth:     'الوزر',
        handle:     'المقبض'
      }.freeze

      FACE_LABELS = {
        front: 'أمامي', back: 'خلفي', left: 'يسار',
        right: 'يمين', top: 'أعلى', bottom: 'أسفل'
      }.freeze

      MATERIAL_LABELS = {
        white: 'شريط ابيض مط1',
        plain: 'شريط سادة',
        dark:  'مفحار1'
      }.freeze

      ARABIC_DIGITS = %w[٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩].freeze
    end
  end
end