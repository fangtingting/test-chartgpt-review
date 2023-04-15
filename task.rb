# 录音抽查-关联信息员通话录音 http://jira.rccchina.com/browse/BEN-1034
module Bll
  module Inquire
    class TaskAssociatedCall
      attr_accessor :recall

      def initialize(_recall)
        self.recall = _recall
      end

      def perform
        return unless check_all?

        save_phone_recall_id
      end

      # 新关联的通话录音需要修改询价的录音抽查状态
      def set_to_be_checked
        Ora::TaskRecordSpotCheck.set_to_be_checked(recall.inquire_id, recall.task_id)
      end

      # 保存通话记录id
      def save_phone_recall_id
        _call_id = latest_call_id
        return if _call_id.blank?

        recall.phone_recall_id = _call_id
        recall.save!
        set_to_be_checked
      end

      def check_all?
        return false unless check_recall_type?

        return false unless check_post?

        true
      end

      # 添加“联系客户”类型跟进并且有选择项
      def check_recall_type?
        recall.recall_type == 'notice_customer' && recall.notice_customer_type.present?
      end

      # 是信息员
      def check_post?
        Ora::Employee.find_by_id(recall.employee_id).researcher_or_inquire?
      end

      # 获取10分钟内最近的一次通话id
      def latest_call_id
        _conditions = {
          type: 1,
          page: 1,
          per_page: 1,
          others: { remote_url: true },
          employee_id: recall.employee_id,
          sort: 'phone_time desc',
          fields: "id,call_sec,monitor_file_name,remote_url",
          phone_time: ['range', (recall.created_at - 10.minutes).strftime('%Y-%m-%d %H:%M:%S'), recall.created_at.strftime('%Y-%m-%d %H:%M:%S')],
          call_sec: ['range', 1, nil]
        }
        _latest_call = Util::PhoneCloudApi.search_phone_records(_conditions)
        _res = _latest_call.fetch('data', {})
        return if _res['data'].blank?

        _phone = _res['data'][0]
        # 不符合条件的提前排除，方便在price中使用
        return _phone['id'] if _phone['call_sec'].to_i > 0 && (_phone['monitor_file_name'].present? || _phone['remote_url'].present?)

        OperateLog.create(operate_type: 17, target_id: recall.id, log_content: _res.to_json)
        nil
      end
    end
  end
end
