# encoding: UTF-8
# =============================================================================
# نافذة تعديل الحوض — v2
# =============================================================================

require 'sketchup.rb'
require 'json'

module CabinetNeo
  module UI
    class SinkPopup
      DIALOG_OPTIONS = {
        dialog_title:    'Cabinet Neo - تعديل الحوض',
        preferences_key: 'CabinetNeo_SinkPopup',
        scrollable:      true,
        resizable:       true,
        width:           400,
        height:          620,
        min_width:       380,
        min_height:      500,
        style:           ::UI::HtmlDialog::STYLE_DIALOG
      }.freeze

      SHAPE_OPTIONS = {
        'rectangle' => 'مستطيل',
        'double'    => 'مزدوج',
        'round'     => 'دائري'
      }.freeze

      COLOR_OPTIONS = {
        '#bec3c8' => 'ستانلس فاتح',
        '#8a8f94' => 'ستانلس غامق',
        '#2a2a2a' => 'أسود مطفي',
        '#c9a961' => 'نحاسي',
        '#e0c89a' => 'ذهبي'
      }.freeze

      class << self
        def instance; @instance ||= new; end
        def is_showing?; @is_showing == true; end
        def set_showing(val); @is_showing = val; end
      end

      def initialize
        @dialog = nil
        @current_sink = nil
      end

      def toggle_for_selection
        if visible?; hide; return; end

        model = Sketchup.active_model
        sel = model.selection.first

        unless sink?(sel)
          ::UI.messagebox("الرجاء تحديد حوض أولاً.", ::MB_OK, 'Cabinet Neo')
          return
        end

        show(sel)
      end

      def show(instance)
        return unless sink?(instance)
        return if SinkPopup.is_showing?

        SinkPopup.set_showing(true)
        begin
          @current_sink = instance

          if @dialog
            begin
              @dialog.show unless @dialog.visible?
              @dialog.bring_to_front
            rescue StandardError
              @dialog = nil
              build_dialog
              @dialog.show
            end
          else
            build_dialog
            @dialog.show
          end

          push_current_data
        ensure
          SinkPopup.set_showing(false)
        end
      rescue StandardError => e
        puts "[SinkPopup] show error: #{e.message}"
        SinkPopup.set_showing(false)
      end

      def hide
        return unless @dialog
        begin
          @dialog.close if @dialog.visible?
        rescue StandardError
        end
      end

      def dispose
        return unless @dialog
        begin
          @dialog.close if @dialog.respond_to?(:visible?) && @dialog.visible?
        rescue StandardError
        end
        @dialog = nil
        @current_sink = nil
      end

      def visible?
        return false unless @dialog
        @dialog.visible? == true
      rescue StandardError
        false
      end

      private

      def sink?(entity)
        return false unless entity.is_a?(Sketchup::ComponentInstance)
        entity.definition.get_attribute('CabinetNeo', 'is_sink', false) ? true : false
      rescue StandardError
        false
      end

      def build_dialog
        @dialog = ::UI::HtmlDialog.new(DIALOG_OPTIONS)
        register_callbacks
        @dialog.set_html(popup_html)
        attach_on_closed
      end

      def attach_on_closed
        return unless @dialog.respond_to?(:set_on_closed)
        dlg = @dialog
        dlg.set_on_closed do
          if @dialog.nil? || @dialog.equal?(dlg)
            @dialog = nil
            @current_sink = nil
          end
        end
      rescue StandardError
      end

      def register_callbacks
        @dialog.add_action_callback('snp_ready')   { |_c|       on_ready }
        @dialog.add_action_callback('snp_apply')   { |_c, json| on_apply(json) }
        @dialog.add_action_callback('snp_delete')  { |_c|       on_delete }
        @dialog.add_action_callback('snp_close')   { |_c|       hide }
      end

      def on_ready
        push_current_data
      end

      def push_current_data
        return unless @dialog
        inst = resolve_sink
        return unless inst

        defn = inst.definition
        data = {
          name:   inst.name,
          width:  (defn.get_attribute('CabinetNeo', 'sink_w', 800).to_f / 10).round,
          depth:  (defn.get_attribute('CabinetNeo', 'sink_d', 450).to_f / 10).round,
          height: (defn.get_attribute('CabinetNeo', 'sink_h', 180).to_f / 10).round,
          rim_w:  (defn.get_attribute('CabinetNeo', 'rim_w', 30).to_f / 10).round,
          shape:  defn.get_attribute('CabinetNeo', 'shape',  'rectangle').to_s,
          color:  defn.get_attribute('CabinetNeo', 'color',  '#bec3c8').to_s,
          bowls:  defn.get_attribute('CabinetNeo', 'bowls',  1).to_i
        }

        shapes  = SHAPE_OPTIONS.map  { |k, v| { id: k, label: v } }
        colors  = COLOR_OPTIONS.map  { |k, v| { id: k, label: v } }

        payload = data.merge(shapes: shapes, colors: colors)
        @dialog.execute_script(
          "window.CabinetNeoSink && window.CabinetNeoSink.receive(#{payload.to_json});"
        )
      rescue StandardError => e
        puts "[SinkPopup] push error: #{e.message}"
      end

      def resolve_sink
        if @current_sink && @current_sink.valid?
          return @current_sink
        end
        model = Sketchup.active_model
        sel = model.selection.first
        return sel if sink?(sel)
        nil
      end

      def on_apply(json)
        data = parse_json(json)
        inst = resolve_sink
        return unless inst

        model = Sketchup.active_model
        rebuild_needed = false
        model.start_operation('تعديل الحوض', true)
        begin
          old_tr = inst.transformation
          defn = inst.definition
          ow = defn.get_attribute('CabinetNeo', 'sink_w', 800).to_f
          od = defn.get_attribute('CabinetNeo', 'sink_d', 450).to_f
          center = old_tr * Geom::Point3d.new((ow / 2.0).mm, (od / 2.0).mm, 0)
          nw = (data['width'] || 80).to_f * 10
          nd = (data['depth'] || 45).to_f * 10
          size_changed = (nw - ow).abs > 0.5 || (nd - od).abs > 0.5 ||
                         ((data['rim_w'] || 3).to_f * 10 - defn.get_attribute('CabinetNeo', 'rim_w', 30).to_f).abs > 0.5

          begin
            inst.erase! if inst.valid?
          rescue StandardError
          end

          tool = ::CabinetNeo::Tools::SinkTool.new(
            width:  (data['width']  || 80).to_f * 10,
            depth:  (data['depth']  || 45).to_f * 10,
            height: (data['height'] || 18).to_f * 10,
            rim:    (data['rim_w']  || 3).to_f * 10,
            shape:  data['shape']  || 'rectangle',
            color:  data['color']  || '#bec3c8',
            bowls:  data['bowls']  || 1
          )

          sink_def = tool.get_or_create_sink_definition(model)
          unless sink_def
            raise "فشل إنشاء تعريف الحوض"
          end

          # نفس الاتجاه ونفس المركز بعد تغيير المقاس
          shift = old_tr * Geom::Point3d.new(0, 0, 0)
          rot_only = Geom::Transformation.new(old_tr.to_a)
          new_origin = center - (rot_only.xaxis.clone.tap { |v| v.length = (nw / 2.0).mm }) -
                       (rot_only.yaxis.clone.tap { |v| v.length = (nd / 2.0).mm })
          new_origin.z = shift.z
          new_tr = Geom::Transformation.axes(new_origin, rot_only.xaxis, rot_only.yaxis, rot_only.zaxis)
          new_inst = model.entities.add_instance(sink_def, new_tr)
          new_inst.name = data['name'] || 'حوض'

          begin
            defn.erase! if defn.valid? && defn.instances.empty?
          rescue StandardError
          end

          model.selection.clear
          model.selection.add(new_inst)
          model.commit_operation
          model.active_view.invalidate

          @current_sink = new_inst
          push_current_data
          flash_status('ok', 'تم التعديل')
          rebuild_needed = size_changed
        rescue StandardError => e
          model.abort_operation
          puts "[SinkPopup] apply error: #{e.message}"
          puts e.backtrace.first(6).join("\n")
          flash_status('err', e.message)
        end

        # المقاس اتغيّر → نعيد بناء الرخامة (بترجّع قصّات كل الأحواض)
        if rebuild_needed && defined?(::CabinetNeo::Geometry::CountertopBuilder)
          res = ::CabinetNeo::Geometry::CountertopBuilder.build_for_lower_units
          puts "[SinkPopup] countertop rebuilt: #{res.inspect}"
        end
      end

      def on_delete
        inst = resolve_sink
        return unless inst

        model = Sketchup.active_model
        model.start_operation('حذف الحوض', true)
        begin
          inst.erase! if inst.valid?
          model.commit_operation
        rescue StandardError
          model.abort_operation
        end
        @current_sink = nil
        hide
      end

      def parse_json(str)
        return {} if str.nil? || str.to_s.strip.empty?
        JSON.parse(str.to_s)
      rescue StandardError
        {}
      end

      def flash_status(kind, msg)
        return unless @dialog
        safe = msg.to_s.gsub("'", "\\\\'")
        @dialog.execute_script(
          "window.CabinetNeoSink && window.CabinetNeoSink.flash('#{kind}','#{safe}');"
        )
      rescue StandardError
      end

      def popup_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="ar" dir="rtl">
          <head>
          <meta charset="UTF-8">
          <style>
            :root{
              --bg:#0b0e13;--card:#171c25;--input:#0e1218;
              --border:#232a35;--border-2:#2d3644;
              --text:#e6e9ee;--text-2:#9aa3b1;--text-3:#6b7382;
              --accent:#ff6b1a;--accent-2:#ff8c42;--danger:#ef4444;
            }
            *{box-sizing:border-box;}
            html,body{margin:0;height:100%;background:var(--bg);color:var(--text);
              font-family:-apple-system,"Segoe UI",Tahoma,sans-serif;font-size:13px;
              user-select:none;overflow:hidden;}
            ::-webkit-scrollbar{width:6px;}
            ::-webkit-scrollbar-thumb{background:#2a323e;border-radius:3px;}
            .wrap{padding:12px;display:flex;flex-direction:column;gap:10px;height:100vh;overflow-y:auto;}
            .header{display:flex;align-items:center;justify-content:space-between;
              padding-bottom:8px;border-bottom:1px solid var(--border);}
            .title{font-size:13px;font-weight:700;color:#5aa9e6;display:flex;gap:8px;align-items:center;}
            .close-x{width:24px;height:24px;border:0;background:transparent;
              color:var(--text-3);cursor:pointer;border-radius:5px;font-size:14px;}
            .close-x:hover{background:#1a2029;color:var(--text);}
            .section{background:var(--card);border:1px solid var(--border);
              border-radius:8px;padding:10px;}
            .section-title{font-size:11px;font-weight:700;color:var(--text-2);
              margin-bottom:8px;padding-bottom:5px;border-bottom:1px solid var(--border);
              text-transform:uppercase;letter-spacing:.5px;}
            .row{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px;}
            .field{display:flex;flex-direction:column;gap:3px;}
            .field-label{font-size:11px;color:var(--text-2);display:flex;justify-content:space-between;}
            .field-label .unit{color:var(--text-3);font-size:10px;}
            .ctrl{display:flex;align-items:center;background:var(--input);
              border:1px solid var(--border-2);border-radius:5px;height:32px;padding:0 8px;}
            .ctrl input{flex:1;background:transparent;border:0;outline:0;
              color:var(--text);font-size:13px;font-weight:700;text-align:center;
              -moz-appearance:textfield;}
            .ctrl input::-webkit-inner-spin-button,
            .ctrl input::-webkit-outer-spin-button{-webkit-appearance:none;}
            .shapes,.colors{display:grid;gap:6px;margin-top:4px;}
            .shapes{grid-template-columns:repeat(3,1fr);}
            .colors{grid-template-columns:repeat(5,1fr);}
            .opt{padding:8px 4px;background:var(--input);
              border:1.5px solid var(--border-2);border-radius:5px;
              text-align:center;cursor:pointer;color:var(--text-2);
              font-family:inherit;font-size:11px;font-weight:600;}
            .opt:hover{border-color:#3a4453;color:var(--text);}
            .opt.active{border-color:#5aa9e6;
              background:linear-gradient(180deg,rgba(90,169,230,.15),rgba(90,169,230,.03));
              color:#fff;}
            .color-swatch{
              display:flex;flex-direction:column;align-items:center;gap:4px;
              padding:6px 2px;background:var(--input);border:1.5px solid var(--border-2);
              border-radius:5px;cursor:pointer;font-size:9px;color:var(--text-2);
            }
            .color-swatch .dot{width:22px;height:22px;border-radius:50%;
              border:1px solid rgba(255,255,255,.15);}
            .color-swatch:hover{border-color:#3a4453;}
            .color-swatch.active{border-color:#5aa9e6;color:#fff;}
            .actions{display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-top:6px;}
            .btn{padding:11px;border-radius:6px;font-family:inherit;
              font-size:13px;font-weight:700;cursor:pointer;border:0;}
            .btn-primary{background:linear-gradient(180deg,var(--accent-2),var(--accent));
              color:#fff;box-shadow:0 3px 10px rgba(255,107,26,.28);}
            .btn-primary:hover{filter:brightness(1.08);}
            .btn-danger{background:#1a2029;color:var(--danger);
              border:1px solid rgba(239,68,68,.35);}
            .btn-danger:hover{background:rgba(239,68,68,.15);}
            .status{font-size:11px;color:var(--text-3);text-align:center;min-height:14px;}
            .status.ok{color:#22c55e;}
            .status.err{color:var(--danger);}
          </style>
          </head>
          <body>
            <div class="wrap">
              <div class="header">
                <div class="title">
                  <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8">
                    <path d="M3 11h18v2a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4v-2z"/>
                    <path d="M6 5v6M18 5v6M12 5v3"/>
                  </svg>
                  تعديل الحوض <span id="sinkName" style="color:var(--text-2);font-weight:500;font-size:11.5px;"></span>
                </div>
                <button class="close-x" id="closeBtn">✕</button>
              </div>

              <div class="section">
                <div class="section-title">📐 المقاسات</div>
                <div class="row">
                  <div class="field">
                    <div class="field-label"><span>العرض</span><span class="unit">سم</span></div>
                    <div class="ctrl"><input type="number" id="width" min="20" max="150" value="80"/></div>
                  </div>
                  <div class="field">
                    <div class="field-label"><span>العمق</span><span class="unit">سم</span></div>
                    <div class="ctrl"><input type="number" id="depth" min="20" max="100" value="45"/></div>
                  </div>
                </div>
                <div class="row">
                  <div class="field">
                    <div class="field-label"><span>الارتفاع</span><span class="unit">سم</span></div>
                    <div class="ctrl"><input type="number" id="height" min="10" max="40" value="18"/></div>
                  </div>
                  <div class="field">
                    <div class="field-label"><span>عرض الشفة</span><span class="unit">سم</span></div>
                    <div class="ctrl"><input type="number" id="rim_w" min="1" max="15" value="3"/></div>
                  </div>
                </div>
              </div>

              <div class="section">
                <div class="section-title">🔷 الشكل</div>
                <div class="shapes" id="shapeOpts"></div>
              </div>

              <div class="section">
                <div class="section-title">🎨 اللون</div>
                <div class="colors" id="colorOpts"></div>
              </div>

              <div class="actions">
                <button class="btn btn-primary" id="applyBtn">تطبيق</button>
                <button class="btn btn-danger" id="deleteBtn">حذف</button>
              </div>
              <div class="status" id="status"></div>
            </div>

            <script>
              (function(){
                var state = { shape:'rectangle', color:'#bec3c8', name:'' };

                function setStatus(kind,msg){
                  var el=document.getElementById('status');
                  if(!el)return; el.textContent=msg||'';
                  el.className='status'+(kind?' '+kind:'');
                }
                function flash(kind,msg){
                  setStatus(kind,msg);
                  setTimeout(function(){setStatus('','');},2500);
                }
                function callRuby(name){
                  var args=Array.prototype.slice.call(arguments,1);
                  if(!window.sketchup||typeof window.sketchup[name]!=='function')return false;
                  try{window.sketchup[name].apply(null,args);return true;}catch(e){setStatus('err',e.message);return false;}
                }
                function renderOptions(){
                  var shapes = document.getElementById('shapeOpts');
                  shapes.innerHTML = state.shapes.map(function(s){
                    return '<button class="opt'+(s.id===state.shape?' active':'')+'" data-shape="'+s.id+'">'+s.label+'</button>';
                  }).join('');

                  var colors = document.getElementById('colorOpts');
                  colors.innerHTML = state.colors.map(function(c){
                    return '<button class="color-swatch'+(c.id===state.color?' active':'')+'" data-color="'+c.id+'" title="'+c.label+'">'
                      + '<div class="dot" style="background:'+c.id+'"></div>'
                      + '<span>'+c.label+'</span></button>';
                  }).join('');

                  document.querySelectorAll('[data-shape]').forEach(function(b){
                    b.addEventListener('click',function(){
                      state.shape = b.getAttribute('data-shape');
                      renderOptions();
                    });
                  });
                  document.querySelectorAll('[data-color]').forEach(function(b){
                    b.addEventListener('click',function(){
                      state.color = b.getAttribute('data-color');
                      renderOptions();
                    });
                  });
                }

                window.CabinetNeoSink = {
                  receive: function(data){
                    if(!data)return;
                    state.shapes  = data.shapes  || [];
                    state.colors  = data.colors  || [];
                    state.shape   = data.shape   || 'rectangle';
                    state.color   = data.color   || '#bec3c8';
                    state.name    = data.name    || '';

                    document.getElementById('sinkName').textContent = state.name;
                    document.getElementById('width').value  = data.width;
                    document.getElementById('depth').value  = data.depth;
                    document.getElementById('height').value = data.height;
                    document.getElementById('rim_w').value  = data.rim_w;

                    renderOptions();
                  },
                  flash: flash
                };

                document.getElementById('applyBtn').addEventListener('click',function(){
                  var payload = {
                    name:   state.name,
                    width:  parseFloat(document.getElementById('width').value)  || 80,
                    depth:  parseFloat(document.getElementById('depth').value)  || 45,
                    height: parseFloat(document.getElementById('height').value) || 18,
                    rim_w:  parseFloat(document.getElementById('rim_w').value)  || 3,
                    shape:  state.shape,
                    color:  state.color
                  };
                  this.disabled = true;
                  setStatus('','جاري التطبيق...');
                  var ok = callRuby('snp_apply', JSON.stringify(payload));
                  if(!ok) this.disabled = false;
                });

                document.getElementById('deleteBtn').addEventListener('click',function(){
                  if(confirm('حذف الحوض؟')) callRuby('snp_delete');
                });
                document.getElementById('closeBtn').addEventListener('click',function(){
                  callRuby('snp_close');
                });

                function ready(attempt){
                  attempt = attempt||1;
                  if(window.sketchup && typeof window.sketchup.snp_ready === 'function'){
                    callRuby('snp_ready');
                    return;
                  }
                  if(attempt < 30) setTimeout(function(){ready(attempt+1);},100);
                }
                if(document.readyState === 'loading'){
                  document.addEventListener('DOMContentLoaded',function(){ready(1);});
                } else { ready(1); }
              })();
            </script>
          </body>
          </html>
        HTML
      end
    end
  end
end

puts '[Cabinet Neo] ✅ sink_popup.rb loaded'