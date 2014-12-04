require 'resque/server'
require 'resque/scheduler/server'

Rails.application.routes.draw do
  devise_for :users, controllers: {omniauth_callbacks: "omniauth_callbacks"}
  guisso_for :user
  root :to => 'home#index'

  get 'angular/*path' => 'home#angular_template'

  resources :connectors, except: [:show] do
    member do
      post 'invoke/*path' => 'connectors#invoke'
      put 'poll'
    end

    collection do
      get 'google_spreadsheets_callback'
    end
  end

  scope :api do
    get 'connectors' => 'api#connectors'
    get 'reflect/connectors/:id' => 'api#reflect', as: 'reflect_api'
    get 'reflect/connectors/:id/*path' => 'api#reflect', as: 'reflect_with_path_api', format: false
    
    scope :data do
      get    'connectors/:id(/*path)'  => 'api#query', as: 'data_with_path_api', format: false
      post   'connectors/:id(/*path)'  => 'api#insert'
      put    'connectors/:id(/*path)'  => 'api#update'
      delete 'connectors/:id(/*path)'  => 'api#delete'
    end

    get 'picker' => 'api#picker'
    post 'notify/connectors/:id/*path'=> 'api#notify'
  end

  resources :event_handlers
  resources :activities, only: :index

  mount Resque::Server.new, at: '/_resque', constraints: { ip: '127.0.0.1' }
end
