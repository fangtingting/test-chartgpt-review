class Account < Ora
  # 创建子/分账号最大可用询价条数
  def self.create_record(current_user, user_id, inquire_count_type, inquire_count)
    _subscriber = Ora::Subscriber.find_by_id(user_id)
    return if _subscriber.blank? || _subscriber.is_parent? # 父账号不生成这个记录

    _parent_subscriber = _subscriber.parent_subscriber # 父账号
    _subscriptions = _parent_subscriber.valid_subscriptions # 有效的订阅
    _subscriptions.each do |_subscription|
      _user_account_inquire_count = AccountMaxInquireCount.first(conditions: ["subscriber_id=? and subscription_id=?", user_id, _subscription.id])
      _note = inquire_count_type.to_i == 1 ? "分配" : "共享"
      if _user_account_inquire_count.blank?
        _modify_content = { note: _note, old_max_inquire_count: 0, new_max_inquire_count: inquire_count }
        AccountMaxInquireCount.create(subscriber_id: user_id, subscription_id: _subscription.id, max_inquire_count: inquire_count, inquire_count_type: inquire_count_type)

      else
        _modify_content = { note: _note, old_max_inquire_count: 0, new_max_inquire_count: _user_account_inquire_count.max_inquire_count }
        _user_account_inquire_count.update_attributes!(max_inquire_count: inquire_count)
      end
      MaxInquireCountRecord.create(subscriber_id: user_id, subscription_id: _subscription.id, updated_by: current_user.id, modify_content: _modify_content.to_json)
    end
  end
end
