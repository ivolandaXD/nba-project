Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post 'auth/register', to: 'auth#register'
      post 'auth/login', to: 'auth#login'

      namespace :nba do
        resources :games, only: %i[index show] do
          member do
            post :fetch_odds
            post :analyze
          end
          resources :players, only: [:index], controller: 'game_players'
        end
        resources :players, only: [] do
          member do
            post :fetch_game_logs
          end
        end
      end

      resources :comments, only: %i[index create]
      resources :bets, only: %i[index create]
      resources :alerts, only: %i[index create update]
      get :ranking, to: 'ranking#index'
    end
  end

  devise_for :users, skip: [:registrations], controllers: { sessions: 'users/sessions' }

  scope module: 'web' do
    root 'dashboard#index'
    post 'dashboard/sync_games', to: 'dashboard#sync_games'

    resources :games, only: [:show] do
      member do
        post :fetch_odds
        post :import_game_logs
        post :analyze
      end
      resources :comments, only: [:create]
      resources :bets, only: [:create]
    end

    resources :players, only: [:show] do
      resources :alerts, only: [:create], controller: 'player_alerts'
    end

    get 'ranking', to: 'ranking#index'
  end
end
