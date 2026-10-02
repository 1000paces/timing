module CurrentOfficial
  extend ActiveSupport::Concern

  private

  def current_official
    return @current_official if defined?(@current_official)
    @current_official = Official.active.find_by(id: session[:official_id])
  end
end
