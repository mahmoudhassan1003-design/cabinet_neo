# encoding: UTF-8
# =============================================================================
# مراقب تغيير الموديل — يعيد ربط Selection Observer عند فتح/إنشاء نموذج
# =============================================================================

module CabinetNeo
  module UI
    class ModelObserver < Sketchup::AppObserver
      def initialize
        super
      end

      # يُستدعى عند إنشاء نموذج جديد
      def onNewModel(_model)
        CabinetNeo.reattach_observer
      end

      # يُستدعى عند فتح نموذج موجود
      def onOpenModel(_model)
        CabinetNeo.reattach_observer
      end
    end
  end
end