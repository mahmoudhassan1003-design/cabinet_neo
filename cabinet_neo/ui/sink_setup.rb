# encoding: UTF-8
# =============================================================================
# نافذة مقاس الحوض قبل الإنشاء — v1
# =============================================================================
# بتظهر لما تدوس زرار "حوض": تختار العرض والعمق والارتفاع وعرض الشفة والشكل
# واللون، وبعدها تضغط "اختيار المكان" وتحدد موضع الحوض على الرخامة.
# القيم بتتحفظ وتترجع في المرة الجاية.
# =============================================================================

require 'sketchup.rb'
require 'json'

module CabinetNeo
  module UI
    class SinkSetup
      PREF_SECTION = 'CabinetNeo_SinkSetup'.freeze

      DEFAULTS = {
        'width' => 80, 'depth' => 45, 'height' => 18, 'rim' => 3,
        'shape' => 'rectangle', 'color' => '#bec3c8'
      }.freeze

      LIMITS = {
        'width'  => [20, 150], 'depth' => [20, 100],
        'height' => [10, 40],  'rim'   => [1, 15]
      }.freeze

      SHAPES = [['rectangle', 'مستطيل'], ['double', 'مزدوج'], ['round', 'دائري']].freeze
      COLORS = [['#bec3c8', 'ستانلس فاتح'], ['#8a8f94', 'ستانلس غامق'], ['#2a2a2a', 'أسود مطفي'],
                ['#c9a961', 'نحاسي'], ['#e0c89a', 'ذهبي']].freeze

      class << self
        def instance; @instance ||= new; end
      end

      def initialize
        @dialog = nil
      end

      def show(theme = nil)
        @theme = theme
        close_existing
        @dialog = ::UI::HtmlDialog.new(
          dialog_title: 'Cabinet Neo - مقاس الحوض',
          preferences_key: 'CabinetNeo_SinkSetup',
          scrollable: false, resizable: false,
          width: 380, height: 520, min_width: 360, min_height: 480,
          style: ::UI::HtmlDialog::STYLE_DIALOG
        )
        @dialog.add_action_callback('ss_ready')  { |_c| push_values }
        @dialog.add_action_callback('ss_place')  { |_c, json| on_place(json) }
        @dialog.add_action_callback('ss_cancel') { |_c| close_existing }
        @dialog.set_html(html)
        @dialog.show
      rescue StandardError => e
        puts "[SinkSetup] show: #{e.message}"
      end

      def close_existing
        d = @dialog
        @dialog = nil
        d.close if d && (d.visible? rescue false)
      rescue StandardError
      end

      private

      def load_values
        raw = Sketchup.read_default(PREF_SECTION, 'values', nil)
        saved = raw ? JSON.parse(raw) : {}
        DEFAULTS.merge(saved.select { |k, _| DEFAULTS.key?(k) })
      rescue StandardError
        DEFAULTS.dup
      end

      def push_values
        return unless @dialog
        payload = load_values.merge(
          'shapes' => SHAPES.map { |i, l| { 'id' => i, 'label' => l } },
          'colors' => COLORS.map { |i, l| { 'id' => i, 'label' => l } }
        )
        @dialog.execute_script("window.CabinetNeoSinkSetup && window.CabinetNeoSinkSetup.receive(#{payload.to_json});")
      end

      def clamp(key, val)
        lo, hi = LIMITS[key]
        v = val.to_f
        v = DEFAULTS[key].to_f if v <= 0
        [[v, lo].max, hi].min
      end

      def on_place(json)
        data = (JSON.parse(json.to_s) rescue {})
        vals = {
          'width'  => clamp('width',  data['width']),
          'depth'  => clamp('depth',  data['depth']),
          'height' => clamp('height', data['height']),
          'rim'    => clamp('rim',    data['rim']),
          'shape'  => SHAPES.map(&:first).include?(data['shape']) ? data['shape'] : 'rectangle',
          'color'  => COLORS.map(&:first).include?(data['color']) ? data['color'] : '#bec3c8'
        }
        # الشفة لازم تكون أصغر من نص العرض والعمق
        max_rim = [vals['width'], vals['depth']].min / 2.0 - 2
        vals['rim'] = [vals['rim'], max_rim].min

        Sketchup.write_default(PREF_SECTION, 'values', vals.to_json)
        close_existing

        tool = ::CabinetNeo::Tools::SinkTool.new(
          width:  vals['width']  * 10, depth: vals['depth'] * 10,
          height: vals['height'] * 10, rim:   vals['rim']   * 10,
          shape:  vals['shape'],       color: vals['color']
        )
        Sketchup.active_model.select_tool(tool)
        puts "[SinkSetup] 🚰 tool armed #{vals.inspect}"
      rescue StandardError => e
        puts "[SinkSetup] on_place: #{e.message}"
        ::UI.messagebox("❌ #{e.message}", ::MB_OK, 'Cabinet Neo')
      end

      def theme_css
        t = @theme.is_a?(Hash) ? @theme : {}
        pairs = {
          '--bg' => t['bg'], '--card' => t['card'], '--input' => t['panel'], '--border' => t['border'],
          '--border-2' => t['border2'], '--text' => t['text'], '--text-2' => t['text2'], '--text-3' => t['text3'],
          '--accent' => t['accent'], '--accent-2' => t['accent2']
        }
        pairs.reject { |_, v| v.to_s.empty? || v.to_s =~ /[;{}<>]/ }.map { |k, v| "#{k}:#{v};" }.join
      end

      def html
        <<~HTML
          <!DOCTYPE html>
          <html lang="ar" dir="rtl"><head><meta charset="UTF-8">
          <style>
            :root{--bg:#0b0e13;--card:#171c25;--input:#0e1218;--border:#232a35;--border-2:#2d3644;
              --text:#e6e9ee;--text-2:#9aa3b1;--text-3:#6b7382;--accent:#ff6b1a;--accent-2:#ff8c42;#{theme_css}}
            *{box-sizing:border-box}
            html,body{margin:0;height:100%;background:var(--bg);color:var(--text);
              font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;font-size:13px;user-select:none}
            .wrap{padding:14px;display:flex;flex-direction:column;gap:10px;height:100%}
            h1{font-size:14px;margin:0 0 2px;color:#5aa9e6}
            .sec{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:10px}
            .st{font-size:11px;font-weight:700;color:var(--text-2);margin-bottom:8px}
            .row{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px}.row:last-child{margin-bottom:0}
            label{display:flex;flex-direction:column;gap:3px;font-size:11px;color:var(--text-2)}
            label span.u{color:var(--text-3);font-size:10px}
            input{background:var(--input);border:1px solid var(--border-2);border-radius:5px;height:32px;
              color:var(--text);font-size:13px;font-weight:700;text-align:center;outline:0}
            input:focus{border-color:var(--accent)}
            .opts{display:grid;gap:6px}.shapes{grid-template-columns:repeat(3,1fr)}.colors{grid-template-columns:repeat(5,1fr)}
            .opt,.sw{background:var(--input);border:1.5px solid var(--border-2);border-radius:5px;color:var(--text-2);
              cursor:pointer;font-family:inherit;font-size:11px;font-weight:600;padding:8px 2px}
            .sw{display:flex;flex-direction:column;align-items:center;gap:4px;font-size:9px;padding:6px 2px}
            .sw i{width:22px;height:22px;border-radius:50%;border:1px solid rgba(255,255,255,.2)}
            .opt.on,.sw.on{border-color:#5aa9e6;color:var(--text)}
            .go{margin-top:auto;display:grid;grid-template-columns:2fr 1fr;gap:8px}
            button.b{padding:11px;border-radius:6px;border:0;font-family:inherit;font-size:13px;font-weight:700;cursor:pointer}
            .p{background:linear-gradient(180deg,var(--accent-2),var(--accent));color:#fff}
            .s{background:var(--card);color:var(--text-2);border:1px solid var(--border-2)}
            .hint{font-size:11px;color:var(--text-3);text-align:center}
          </style></head><body><div class="wrap">
            <h1>🚰 مقاس الحوض قبل الإنشاء</h1>
            <div class="sec"><div class="st">📐 المقاسات (سم)</div>
              <div class="row">
                <label>العرض<input type="number" id="width" min="20" max="150" step="1"></label>
                <label>العمق<input type="number" id="depth" min="20" max="100" step="1"></label>
              </div>
              <div class="row">
                <label>الارتفاع (عمق الحوض)<input type="number" id="height" min="10" max="40" step="1"></label>
                <label>عرض الشفة<input type="number" id="rim" min="1" max="15" step="0.5"></label>
              </div>
            </div>
            <div class="sec"><div class="st">🔷 الشكل</div><div class="opts shapes" id="shapes"></div></div>
            <div class="sec"><div class="st">🎨 اللون</div><div class="opts colors" id="colors"></div></div>
            <div class="hint">بعد الضغط على «اختيار المكان» اضغط على الرخامة لتثبيت الحوض</div>
            <div class="go">
              <button class="b p" id="go">اختيار المكان ◀</button>
              <button class="b s" id="cancel">إلغاء</button>
            </div>
          </div>
          <script>
            (function(){
              var st={shape:'rectangle',color:'#bec3c8',shapes:[],colors:[]};
              function call(n,a){ if(window.sketchup&&typeof window.sketchup[n]==='function') window.sketchup[n](a); }
              function draw(){
                document.getElementById('shapes').innerHTML=st.shapes.map(function(s){
                  return '<button class="opt'+(s.id===st.shape?' on':'')+'" data-s="'+s.id+'">'+s.label+'</button>';}).join('');
                document.getElementById('colors').innerHTML=st.colors.map(function(c){
                  return '<button class="sw'+(c.id===st.color?' on':'')+'" data-c="'+c.id+'"><i style="background:'+c.id+'"></i><span>'+c.label+'</span></button>';}).join('');
                [].forEach.call(document.querySelectorAll('[data-s]'),function(b){b.onclick=function(){st.shape=b.getAttribute('data-s');draw();};});
                [].forEach.call(document.querySelectorAll('[data-c]'),function(b){b.onclick=function(){st.color=b.getAttribute('data-c');draw();};});
              }
              window.CabinetNeoSinkSetup={receive:function(d){
                st.shapes=d.shapes;st.colors=d.colors;st.shape=d.shape;st.color=d.color;
                ['width','depth','height','rim'].forEach(function(k){document.getElementById(k).value=d[k];});
                draw();
              }};
              document.getElementById('go').onclick=function(){
                var p={shape:st.shape,color:st.color};
                ['width','depth','height','rim'].forEach(function(k){p[k]=parseFloat(document.getElementById(k).value);});
                call('ss_place',JSON.stringify(p));
              };
              document.getElementById('cancel').onclick=function(){call('ss_cancel');};
              (function ready(n){ if(window.sketchup&&typeof window.sketchup.ss_ready==='function') call('ss_ready'); else if(n<40) setTimeout(function(){ready(n+1)},100); })(0);
            })();
          </script></body></html>
        HTML
      end
    end
  end
end

puts '[Cabinet Neo] ✅ sink_setup.rb loaded'
