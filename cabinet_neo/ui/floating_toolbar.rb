# encoding: UTF-8
# =============================================================================
# شريط أدوات عائم — v9 (محاذاة + لف + نقل + تبديل الخامة + ثيم + مقاس الحوض)
# =============================================================================

require 'sketchup.rb'
require 'json'

module CabinetNeo
  module UI
    class FloatingToolbar
      DIALOG_OPTIONS = {
        dialog_title:    'Cabinet Neo',
        preferences_key: 'CabinetNeo_FloatingToolbar',
        scrollable:      false,
        resizable:       false,
        width:           90,
        height:          800,
        min_width:       90,
        min_height:      420,
        style:           ::UI::HtmlDialog::STYLE_DIALOG
      }.freeze

      class << self
        def instance; @instance ||= new; end

        # بيستدعيها أدوات النقل/جنب وحدة لما تخلص — بترجّع الشريط اللي اتخفى
        def resume_after_tool
          @instance.resume_after_tool if @instance
        end
      end

      def initialize
        close_old_instances
        @dialog = nil
      end

      def close_old_instances
        begin
          if defined?($cabinet_neo_ftb_dialog) && $cabinet_neo_ftb_dialog
            $cabinet_neo_ftb_dialog.close rescue nil
            $cabinet_neo_ftb_dialog = nil
          end
        rescue StandardError
        end
      rescue StandardError
      end

      def show
        if @dialog
          if (@dialog.visible? rescue false)
            @dialog.bring_to_front rescue nil
            return
          end
          # مقفولة → ابنيها من جديد (إعادة show لنافذة مقفولة بتسيب الأزرار ميتة)
          old = @dialog
          @dialog = nil
          begin; old.close; rescue StandardError; end
        end
        @resume_pending = false
        build_dialog
        @dialog.show
        $cabinet_neo_ftb_dialog = @dialog
        puts '[Cabinet Neo FTB] ✅ Shown'
      rescue StandardError => e
        puts "[Cabinet Neo FTB] show failed: #{e.message}"
      end

      def hide
        return if @dialog.nil?
        old = @dialog
        @dialog = nil
        $cabinet_neo_ftb_dialog = nil
        begin; old.close; rescue StandardError; end
      end

      def dispose
        hide
        @dialog = nil
      rescue StandardError
      end

      def toggle
        if visible?
          hide
        else
          show
        end
      end

      def visible?
        return false if @dialog.nil?
        @dialog.visible?
      rescue StandardError
        false
      end

      # يخفي الشريط مؤقتاً أثناء أداة (نقل / جنب وحدة) — عشان الفوكس يرجع لسكتش أب
      # ومفاتيح Shift / Ctrl تشتغل. بيرجع تلقائي لما الأداة تخلص (deactivate).
      def suspend_for_tool
        return unless visible?
        @resume_pending = true
        hide
      rescue StandardError => e
        puts "[Cabinet Neo FTB] suspend_for_tool: #{e.message}"
      end

      def resume_after_tool
        return unless @resume_pending
        @resume_pending = false
        ::UI.start_timer(0.1, false) { show }
      rescue StandardError => e
        puts "[Cabinet Neo FTB] resume_after_tool: #{e.message}"
      end

      private

      def build_dialog
        @dialog = ::UI::HtmlDialog.new(DIALOG_OPTIONS)
        register_callbacks
        @dialog.set_html(toolbar_html)
        dlg = @dialog
        if dlg.respond_to?(:set_on_closed)
          dlg.set_on_closed do
            if @dialog.nil? || @dialog.equal?(dlg)
              @dialog = nil
              $cabinet_neo_ftb_dialog = nil
            end
          end
        end
        puts '[Cabinet Neo FTB] 🔧 Dialog built'
      end

      def register_callbacks
        {
          'ftb_open_main'         => :on_open_main,
          'ftb_open_popup'        => :on_toggle_popup,
          'ftb_open_doors'        => :on_open_doors,
          'ftb_close_doors'       => :on_close_doors,
          'ftb_create_countertop' => :on_create_countertop,
          'ftb_add_sink'          => :on_add_sink,
          'ftb_align_row'         => :on_align_row,
          'ftb_align_wall'        => :on_align_wall,
          'ftb_rotate_left'       => :on_rotate_left,
          'ftb_rotate_right'      => :on_rotate_right,
          'ftb_move_left'         => :on_move_left,
          'ftb_move_right'        => :on_move_right,
          'ftb_toggle_material'   => :on_toggle_material,
          'ftb_settings'          => :on_open_settings,
          'ftb_hide'              => :hide
        }.each do |name, meth|
          @dialog.add_action_callback(name) do |_c|
            puts "[Cabinet Neo FTB] ▶ #{name}"
            begin
              send(meth)
            rescue StandardError => e
              puts "[Cabinet Neo FTB] ❌ #{name}: #{e.message}"
              puts e.backtrace.first(5).join("\n")
            end
          end
        end
        # أرقام/مفاتيح النقل (الفوكس بيفضل على الشريط بعد الضغط على زرار «نقل»)
        @dialog.add_action_callback('ftb_key') do |_c, key|
          begin
            if defined?(::CabinetNeo::Tools::MoveTool)
              ::CabinetNeo::Tools::MoveTool.handle_key(key)
            end
          rescue StandardError => e
            puts "[Cabinet Neo FTB] ❌ ftb_key: #{e.message}"
          end
        end
        puts '[Cabinet Neo FTB] ✅ Callbacks registered'
      end

      def on_open_main
        CabinetNeo.show_dialog
      rescue StandardError => e
        puts "[Cabinet Neo FTB] open_main: #{e.message}"
      end

            def on_toggle_popup
        model = Sketchup.active_model
        sel = model.selection.first

        # ⭐ حوض؟ افتح نافذة الحوض
        if sel.is_a?(Sketchup::ComponentInstance) &&
           sel.definition.get_attribute('CabinetNeo', 'is_sink', false)
          if defined?(CabinetNeo::UI::SinkPopup)
            CabinetNeo::UI::SinkPopup.instance.toggle_for_selection
          else
            ::UI.messagebox("SinkPopup غير محمّل", ::MB_OK, 'Cabinet Neo')
          end
          return
        end

        # وإلا: نافذة الوحدة
        if defined?(CabinetNeo::UI::SelectionPopup)
          CabinetNeo::UI::SelectionPopup.instance.toggle_for_selection
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] toggle_popup: #{e.message}"
      end

      # الوحدات المحددة (وحدات Cabinet Neo بس)
      def selected_units
        sel = Sketchup.active_model.selection.grep(Sketchup::ComponentInstance)
        sel.select do |i|
          i.valid? && i.definition.get_attribute('CabinetNeo', 'generated', false) &&
            !i.definition.get_attribute('CabinetNeo', 'is_sink', false)
        end
      end

      def move_doors(open)
        units = selected_units
        if units.empty?
          ::UI.messagebox('حدد وحدة (أو أكتر) من وحدات Cabinet Neo الأول.', ::MB_OK, 'Cabinet Neo')
          return
        end
        units.each do |u|
          if open
            ::CabinetNeo::Geometry::CabinetBuilder.open_doors(u)
          else
            ::CabinetNeo::Geometry::CabinetBuilder.close_doors(u)
          end
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] #{open ? 'open' : 'close'}_doors: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      def on_open_doors;  move_doors(true);  end
      def on_close_doors; move_doors(false); end

      def on_create_countertop
        unless defined?(::CabinetNeo::Geometry::CountertopBuilder)
          ::UI.messagebox("CountertopBuilder غير محمّل.", ::MB_OK, 'Cabinet Neo')
          return
        end

        result = ::CabinetNeo::Geometry::CountertopBuilder.build_for_lower_units

        if result[:success]
          puts "[Cabinet Neo] ✅ Countertop: #{result[:count]} units"
          ::UI.messagebox(
            "✅ تم إنشاء الرخامة\n\n" \
            "عدد الوحدات: #{result[:count]}\n" \
            "عدد قطع الرخام: #{result[:pieces]}\n" \
            "العرض: #{(result[:width] / 10).round(1)} سم\n" \
            "العمق: #{(result[:depth] / 10).round(1)} سم",
            ::MB_OK, 'Cabinet Neo'
          )
        else
          ::UI.messagebox("❌ #{result[:reason]}", ::MB_OK, 'Cabinet Neo')
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] countertop error: #{e.message}"
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      # ---------- المحاذاة واللف ----------
      def arrange(kind)
        unless defined?(::CabinetNeo::Geometry::UnitArranger)
          ::UI.messagebox('UnitArranger غير محمّل.', ::MB_OK, 'Cabinet Neo')
          return
        end
        arr   = ::CabinetNeo::Geometry::UnitArranger
        units = arr.selected_units
        if units.empty?
          ::UI.messagebox('حدد وحدة (أو أكتر) من وحدات Cabinet Neo الأول.', ::MB_OK, 'Cabinet Neo')
          return
        end
        res =
          case kind
          when :row   then arr.align_row(units)
          when :wall  then arr.align_to_wall(units)
          when :left  then arr.rotate(units, 90)
          when :right then arr.rotate(units, -90)
          end
        if res && !res[:success]
          ::UI.messagebox("⚠️ #{res[:message]}", ::MB_OK, 'Cabinet Neo')
        elsif res
          Sketchup.status_text = "✅ #{res[:message]}"
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] arrange(#{kind}): #{e.message}"
        puts e.backtrace.first(5).join("\n")
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      # ---------- النقل من الركن العلوي ----------
      def start_move(corner)
        unless defined?(::CabinetNeo::Tools::MoveTool)
          ::UI.messagebox('MoveTool غير محمّل.', ::MB_OK, 'Cabinet Neo')
          return
        end
        units = selected_units
        if units.empty?
          ::UI.messagebox('حدد وحدة (أو أكتر) من وحدات Cabinet Neo الأول.', ::MB_OK, 'Cabinet Neo')
          return
        end
        Sketchup.active_model.select_tool(::CabinetNeo::Tools::MoveTool.new(units, corner))
        suspend_for_tool   # اخفي القائمة أثناء النقل (Shift/Ctrl) — بترجع لما تخلص
      rescue StandardError => e
        puts "[Cabinet Neo FTB] move(#{corner}): #{e.message}"
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      def on_move_left;  start_move(:left);  end
      def on_move_right; start_move(:right); end

      # ---------- تبديل الخامة: سادة ⇄ خشب (داخلي + خارجي) ----------
      def on_toggle_material
        unless defined?(::CabinetNeo::Materials::StyleLibrary)
          ::UI.messagebox('StyleLibrary غير محمّل.', ::MB_OK, 'Cabinet Neo')
          return
        end
        res = ::CabinetNeo::Materials::StyleLibrary.toggle_plain_wood(
          Sketchup.active_model, selected_units
        )
        if res[:success]
          Sketchup.status_text = res[:mode] == 'wood' ? "🪵 تم التحويل إلى خشب (#{res[:units]} وحدة)" : "⬜ تم التحويل إلى سادة (#{res[:units]} وحدة)"
        else
          ::UI.messagebox("⚠️ #{res[:reason]}", ::MB_OK, 'Cabinet Neo')
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] toggle_material: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      # وحدة واحدة محددة → أداة «جنب وحدة تانية» (اختار جنب أي وحدة وتتلزق علطول)
      # وحدتين أو أكتر → رصّهم جنب بعض زي الأول
      def on_align_row
        arr = ::CabinetNeo::Geometry::UnitArranger if defined?(::CabinetNeo::Geometry::UnitArranger)
        units = arr ? arr.selected_units : []
        if arr && units.size == 1
          Sketchup.active_model.select_tool(arr::BesideTool.new(units.first))
          suspend_for_tool   # اخفي القائمة لحد ما تخلص (Shift/Ctrl) — بترجع لوحدها
        else
          arrange(:row)
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] align_row: #{e.message}"
        puts e.backtrace.first(5).join("\n")
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end
      def on_align_wall;   arrange(:wall);  end
      def on_rotate_left;  arrange(:left);  end
      def on_rotate_right; arrange(:right); end

      def on_open_settings
        CabinetNeo.show_dialog
        mgr = ::CabinetNeo::UI::DialogManager.instance
        mgr.send_event('open_settings', {}) if mgr.respond_to?(:send_event)
      rescue StandardError => e
        puts "[Cabinet Neo FTB] open_settings: #{e.message}"
      end

      # ---------- الثيم (بيتزامن مع إعدادات الواجهة الرئيسية) ----------
      public

      THEME_KEYS = {
        'bg' => '--bg', 'panel' => '--panel', 'card' => '--card', 'border' => '--border', 'border2' => '--border-2',
        'text' => '--text', 'text2' => '--text-2', 'hdrA' => '--hdr-a', 'hdrB' => '--hdr-b', 'surf2' => '--surf-2',
        'strong' => '--strong', 'accent' => '--accent', 'accent2' => '--accent-2', 'accentRgb' => '--accent-rgb',
        'radius' => '--radius'
      }.freeze

      # ui = Hash من settings['ui'] — بيتجاهل أي قيمة فيها رموز خطرة
      def apply_theme(ui)
        @theme_vars = sanitize_theme(ui)
        return unless @dialog && (@dialog.visible? rescue false)
        @dialog.execute_script("window.applyTheme && window.applyTheme(#{@theme_vars.to_json});")
      rescue StandardError => e
        puts "[Cabinet Neo FTB] apply_theme: #{e.message}"
      end

      private

      def sanitize_theme(ui)
        return {} unless ui.is_a?(Hash) && ui['syncFtb'] != false
        vars = ui['vars']
        return {} unless vars.is_a?(Hash)
        out = {}
        THEME_KEYS.each do |k, css|
          v = vars[k].to_s.strip
          next if v.empty? || v.length > 60 || v =~ /[;{}<>"'\\]/
          out[css] = v
        end
        out
      end

      def saved_theme
        return @theme_vars if @theme_vars
        path = File.join(__dir__, '..', '..', 'user_settings.json')
        return {} unless File.exist?(path)
        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        @theme_vars = sanitize_theme(data['ui'])
      rescue StandardError
        {}
      end

      def saved_theme_for_dialogs
        path = File.join(__dir__, '..', '..', 'user_settings.json')
        return nil unless File.exist?(path)
        vars = (JSON.parse(File.read(path, encoding: 'UTF-8')).dig('ui', 'vars'))
        return nil unless vars.is_a?(Hash)
        vars.select { |_, v| v.to_s.length < 60 && v.to_s !~ /[;{}<>"'\\]/ }
      rescue StandardError
        nil
      end

      def theme_css_text
        saved_theme.map { |k, v| "#{k}:#{v};" }.join
      end

      # ⭐ زرار الحوض
      def on_add_sink
        unless defined?(::CabinetNeo::Tools::SinkTool)
          ::UI.messagebox("SinkTool غير محمّل.", ::MB_OK, 'Cabinet Neo')
          return
        end

        model = Sketchup.active_model

        # تأكد من وجود رخامة
        has_countertop = false
        model.entities.each do |ent|
          if ent.is_a?(Sketchup::Group) &&
             ent.get_attribute('CabinetNeo', 'is_countertop', false)
            has_countertop = true
            break
          end
        end

        unless has_countertop
          ::UI.messagebox(
            "لا توجد رخامة في المشهد.\n\nأنشئ الرخامة أولاً من زرار 'رخامة'.",
            ::MB_OK, 'Cabinet Neo'
          )
          return
        end

        if defined?(::CabinetNeo::UI::SinkSetup)
          ::CabinetNeo::UI::SinkSetup.instance.show(saved_theme_for_dialogs)
          puts '[Cabinet Neo FTB] 🚰 Sink setup opened'
        else
          model.select_tool(::CabinetNeo::Tools::SinkTool.new)
        end
      rescue StandardError => e
        puts "[Cabinet Neo FTB] add_sink error: #{e.message}"
        ::UI.messagebox("❌ خطأ: #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      def toolbar_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="ar" dir="rtl">
          <head>
            <meta charset="UTF-8">
            <style>
              :root {
                --bg:#1e222b; --panel:#12161d; --card:#252a34; --border:#2f3745; --border-2:#2f3745;
                --text:#e6e9ee; --text-2:#b8c0cc; --hdr-a:#252a34; --hdr-b:#1a1e26; --surf-2:#2f3745;
                --strong:#ffffff; --accent:#ff6b1a; --accent-2:#ff8c42; --accent-rgb:255,107,26; --radius:6px;
                #{theme_css_text}
              }
              * { box-sizing: border-box; margin: 0; padding: 0; }
              html, body {
                height: 100%; background: var(--bg); color: var(--text);
                font-family: -apple-system, "Segoe UI", Tahoma, sans-serif;
                font-size: 10px; user-select: none; overflow-x: hidden; overflow-y: auto;
              }
              ::-webkit-scrollbar { width: 0; }
              .ftb {
                display: flex; flex-direction: column;
                min-height: 100%; padding: 6px 4px; gap: 2px;
                background: linear-gradient(180deg, var(--hdr-a), var(--hdr-b));
              }
              .logo { display: flex; justify-content: center; padding: 2px 0 5px; border-bottom: 1px solid var(--border); margin-bottom: 2px; }
              .logo svg { width: 22px; height: 22px; }
              .btn {
                display: flex; flex-direction: column; align-items: center; justify-content: center;
                gap: 2px; padding: 5px 2px; border: 0; background: transparent;
                color: var(--text-2); cursor: pointer; border-radius: var(--radius);
                font-family: inherit; font-size: 9.5px; font-weight: 600; transition: all .15s ease;
              }
              .btn:hover { background: var(--surf-2); color: var(--strong); }
              .btn:active { transform: scale(0.94); }
              .btn svg { width: 21px; height: 21px; stroke: currentColor; stroke-width: 1.7; fill: none; stroke-linecap: round; stroke-linejoin: round; }
              .btn.primary { background: linear-gradient(180deg, var(--accent-2), var(--accent)); color: #fff; box-shadow: 0 2px 6px rgba(var(--accent-rgb), .35); }
              .btn.primary:hover { filter: brightness(1.1); background: linear-gradient(180deg, var(--accent-2), var(--accent)); }
              .btn.accent { color: #4ec9b0; }
              .btn.accent:hover { background: rgba(78, 201, 176, .15); }
              .btn.water { color: #5aa9e6; }
              .btn.water:hover { background: rgba(90, 169, 230, .15); }
              .btn.arr { color: var(--accent-2); }
              .btn.arr:hover { background: rgba(var(--accent-rgb), .15); }
              .row2 { display: flex; gap: 2px; }
              .row2 .btn { flex: 1; padding: 5px 0; line-height: 1.15; font-size: 9px; }
              .btn.mat { color: #d9a066; }
              .btn.mat:hover { background: rgba(217,160,102,.15); }
              .sep { height: 1px; background: var(--border); margin: 3px 4px; }
              .spacer { flex: 1; min-height: 4px; }
              .btn.danger { color: #ef4444; }
              .btn.danger:hover { background: rgba(239,68,68,.15); }
            </style>
          </head>
          <body>
            <div class="ftb">
              <div class="logo">
                <svg viewBox="0 0 32 32">
                  <defs>
                    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
                      <stop offset="0" stop-color="#ff8c42"/>
                      <stop offset="1" stop-color="#ff5a00"/>
                    </linearGradient>
                  </defs>
                  <path d="M16 3 L29 10 L29 22 L16 29 L3 22 L3 10 Z" fill="url(#g)"/>
                  <path d="M16 3 L29 10 L16 17 L3 10 Z" fill="#ffb37a" opacity=".55"/>
                  <path d="M16 17 L29 10 L29 22 L16 29 Z" fill="#000" opacity=".18"/>
                </svg>
              </div>

              <button class="btn primary" onclick="send('ftb_open_main')" title="المكتبة">
                <svg viewBox="0 0 24 24"><path d="M3 5h18v14H3z"/><path d="M3 9h18M12 5v14"/></svg>
                <span>المكتبة</span>
              </button>
              <button class="btn" onclick="send('ftb_open_popup')" title="تعديل">
                <svg viewBox="0 0 24 24"><path d="M4 20h4l10-10-4-4L4 16z"/><path d="M14 6l4 4"/></svg>
                <span>تعديل</span>
              </button>

              <div class="sep"></div>

              <button class="btn accent" onclick="send('ftb_create_countertop')" title="رخامة">
                <svg viewBox="0 0 24 24"><path d="M2 11h20v3H2z"/><path d="M4 14v7M20 14v7"/></svg>
                <span>رخامة</span>
              </button>
              <button class="btn water" onclick="send('ftb_add_sink')" title="حوض (حدد المقاس)">
                <svg viewBox="0 0 24 24"><path d="M3 11h18v2a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4v-2z"/><path d="M6 6v5M18 6v5"/></svg>
                <span>حوض</span>
              </button>

              <div class="sep"></div>

              <button class="btn arr" onclick="send('ftb_align_row')" title="جنب بعض: حدد وحدة واضغط واختار جنب وحدة تانية — أو حدد وحدتين+ لرصهم">
                <svg viewBox="0 0 24 24"><rect x="2" y="8" width="6" height="9"/><rect x="9" y="8" width="6" height="9"/><rect x="16" y="8" width="6" height="9"/><path d="M2 20.5h20"/></svg>
                <span>جنب بعض</span>
              </button>
              <button class="btn arr" onclick="send('ftb_align_wall')" title="محاذاة على الحيط">
                <svg viewBox="0 0 24 24"><path d="M3 3v18"/><path d="M3 7h3M3 12h3M3 17h3"/><rect x="8" y="8" width="11" height="8"/></svg>
                <span>على الحيط</span>
              </button>
              <button class="btn arr" onclick="send('ftb_rotate_left')" title="لف شمال 90°">
                <svg viewBox="0 0 24 24"><path d="M4 9a8 8 0 1 1-1 5"/><path d="M4 3v6h6"/></svg>
                <span>لف شمال</span>
              </button>
              <button class="btn arr" onclick="send('ftb_rotate_right')" title="لف يمين 90°">
                <svg viewBox="0 0 24 24"><path d="M20 9a8 8 0 1 0 1 5"/><path d="M20 3v6h-6"/></svg>
                <span>لف يمين</span>
              </button>

              <div class="row2">
                <button class="btn arr" onclick="send('ftb_move_right')" title="نقل — مسك الوحدة من ركنها العلوي اليمين">
                  <svg viewBox="0 0 24 24"><rect x="3" y="9" width="13" height="11"/><path d="M16 9V3M16 3l-3 3M16 3l3 3"/><circle cx="16" cy="9" r="1.6" fill="currentColor"/></svg>
                  <span>نقل<br>يمين</span>
                </button>
                <button class="btn arr" onclick="send('ftb_move_left')" title="نقل — مسك الوحدة من ركنها العلوي الشمال">
                  <svg viewBox="0 0 24 24"><rect x="8" y="9" width="13" height="11"/><path d="M8 9V3M8 3L5 6M8 3l3 3"/><circle cx="8" cy="9" r="1.6" fill="currentColor"/></svg>
                  <span>نقل<br>شمال</span>
                </button>
              </div>

              <button class="btn mat" onclick="send('ftb_toggle_material')" title="تبديل الخامة: سادة ⇄ خشب (الأوشاش بس: درف وأدراج)">
                <svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="16" rx="1"/><path d="M3 9h18M3 14h18"/><path d="M7 4v5M15 9v5M9 14v6" opacity=".6"/></svg>
                <span>الخامة</span>
              </button>

              <div class="sep"></div>

              <button class="btn" onclick="send('ftb_open_doors')" title="فتح">
                <svg viewBox="0 0 24 24"><path d="M4 4h7v16H4zM13 12l6-5v10z"/></svg>
                <span>فتح</span>
              </button>
              <button class="btn" onclick="send('ftb_close_doors')" title="إغلاق">
                <svg viewBox="0 0 24 24"><path d="M4 4h7v16H4zM19 12l-6-5v10z"/></svg>
                <span>إغلاق</span>
              </button>

              <div class="spacer"></div>
              <div class="sep"></div>

              <button class="btn" onclick="send('ftb_settings')" title="الإعدادات (ألوان الواجهة)">
                <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1"/></svg>
                <span>إعدادات</span>
              </button>
              <button class="btn danger" onclick="send('ftb_hide')" title="إخفاء">
                <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>
                <span>إخفاء</span>
              </button>
            </div>

            <script>
              // يشتغل مع callbacks سكتش أب، وبديل skp: لو الكائن مش جاهز
              function send(action) {
                try {
                  if (window.sketchup && typeof window.sketchup[action] === 'function') {
                    window.sketchup[action]();
                  } else {
                    window.location = 'skp:' + action;
                  }
                } catch (e) {
                  try { window.location = 'skp:' + action; } catch (e2) {}
                }
              }
              // مفاتيح النقل: أرقام + . , - Backspace Enter Escape → أداة النقل (لو شغالة)
              document.addEventListener('keydown', function (e) {
                var k = e.key;
                if (!/^[0-9.,\-]$/.test(k) && k !== 'Backspace' && k !== 'Enter' && k !== 'Escape') { return; }
                try {
                  if (window.sketchup && typeof window.sketchup.ftb_key === 'function') {
                    window.sketchup.ftb_key(k);
                  } else {
                    window.location = 'skp:ftb_key@' + encodeURIComponent(k);
                  }
                } catch (err) {}
              });
              window.applyTheme = function (vars) {
                var r = document.documentElement.style;
                for (var k in vars) { if (Object.prototype.hasOwnProperty.call(vars, k)) r.setProperty(k, vars[k]); }
              };
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end

puts '[Cabinet Neo FTB] ✅ floating_toolbar.rb loaded at ' + Time.now.strftime('%H:%M:%S')