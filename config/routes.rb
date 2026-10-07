Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  resource :session, only: %i[create show destroy]
  post "devices/pair", to: "devices#pair"
  scope "sync/v1", controller: :sync do
    post "clock"
    post "push"
    get "roster"
    get "status"
  end
  post "graphql", to: "graphql#execute"
  get "console/*path", to: "console#show", format: false
  get "onboarding", to: "onboarding#show"
  get "onboarding/ca.crt", to: "onboarding#ca"
  mount ActionCable.server => "/cable"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
