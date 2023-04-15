# login relate api
class AuthLoginApi < Grape::API
  helpers OAuthHelper
  after do
    record_visit_history
  end
  resources :auth_login do
    desc '不需要登录获取channel'
    params do
      requires :channel_id, type: Integer
    end
    post 'no_login_channel' do
      channel = Customer::AttractChannel.find_by_id(params[:channel_id])
      exception(code: :other_errors, message: '获取二维码失败') if channel.blank?
      response data: channel.to_list_json
    end

    desc '获取跳转auth url', entity: ::SwaggerTags::AuthLogin::AuthUrl
    params do
      optional :to_path, type: String, desc: '跳转路径', coerce_with: ->(path) { CGI.escape(path) }
    end
    get 'auth_url' do
      response data: { url: oauth_url(params[:to_path]) }
    end

    desc '校验登陆成功', entity: ::SwaggerTags::AuthLogin::Authorization
    params do
      requires :code, type: String, desc: 'auth校验token'
      optional :to_path, type: String, desc: '跳转路径'
    end
    post 'authorization' do
      user_info = get_auth_info(params[:code], params[:to_path])
      return response code: :other_errors, message: '鉴权失败，请重试!' if user_info.blank?

      user = User::Employee.find_by_id(user_info['id'])
      session = User::Session.init_session(user, true)
      response data: user.json_data.merge(session_id: session.session_id, operations: user.operations, client_id: Util::ExConfig['oauth']['client_id'], user_position: user.user_position)
    end

    desc '本地的登录接口，不通过auth'
    params do
      requires :sid, type: String, desc: '正式的session_id'
    end
    post 'local_login' do
      session = User::Session.find(params[:sid])
      exception(code: :no_login, message: '登录超时或未登录,请重新登录!') if session.blank?
      user = session.user
      exception(code: :no_login, message: '登录超时或未登录,请重新登录!') if user.blank?
      response data: user.json_data.merge(session_id: session.session_id, operations: user.operations)
    end

    desc '监控登录接口'
    params do
      requires :token, type: String, desc: '校验token'
      requires :username, type: String, desc: '用户名'
    end
    post 'monitor_authorization' do
      monitor_jwt_check(params[:token])
      user = User::Employee.where(username: params[:username])&.first
      return response code: :other_errors, message: '用户名不存在' if user.blank?

      session = User::Session.get_user_session(user.id, user.class.name, 'project-case-ui')
      session ||= User::Session.init_session(user, true)
      response data: { session_id: session.session_id }
    end

    desc '从外部导入甲方公司接口'
    params do
      requires :firm_names, type: Array, desc: '公司名'
    end
    post 'import_party_firm' do
      not_found_firms = []
      params[:firm_names].each do |firm_name|
        next if Supply::PartyFirm.where(firm_name: firm_name).present?

        res = Rcc::ServiceCall.rcc_firm_api.rcc.firm.search_firms_by_name.do(params: { firm_name: firm_name, limit: 1 })
        res.deep_symbolize_keys!

        if res[:data].blank?
          # '北京华业地产股份有限公司（又名：北京华业资本控股股份有限公司）'
          other_name = firm_name.split(/[(（]/)[0]
          next if Supply::PartyFirm.where(firm_name: other_name).present?

          res = Rcc::ServiceCall.rcc_firm_api.rcc.firm.search_firms_by_name.do(params: { firm_name: other_name, limit: 1 })
          res.deep_symbolize_keys!
        end
        if res[:code] != 10_000 || res[:data].blank?
          not_found_firms << firm_name
          next
        end
        firm = res[:data].first
        Supply::PartyFirm.create(key_no: firm[:key_no], firm_name: firm[:name])
      end
      Rails.logger.info "not_found_firms: #{not_found_firms}" if not_found_firms.present?
      response message: 'import success!'
    end

    desc '招外导入甲方公司接口'
    params do
      requires :firms, type: Array, desc: '公司信息'
      requires :source, type: String, desc: '统一公司库来源'
    end
    post 'bid_import_firm' do
      params[:from_type] = 'case-ui'
      res = Rcc::ServiceCall.rcc_firm_api.rcc.firm.search.do(params: { source: params[:source], ids: params[:firms].map { |x| x[:id] } })
      res.deep_symbolize_keys!
      if res[:code] == 10_000
        res[:data].each do |firm|
          next if Supply::PartyFirm.where(firm_name: firm[:qcc_info][:name]).present?

          Supply::PartyFirm.create(key_no: firm[:qcc_info][:key_no], firm_name: firm[:qcc_info][:name])
        end
        firm_ids = res[:data].map { |x| x[:firm_id] }
        not_found_firms = params[:firms].reject { |x| firm_ids.include?(x[:id]) }
        Rails.logger.info "not_found_firms: #{not_found_firms}" if not_found_firms.present?
      elsif not_found_firms.present?
        Rails.logger.info "not_found_firms: #{params[:firms]}"
      end
      Rails.logger.info "not_found_firms"
      response
    end
  end
end
