module Api
  module V1
    class AuthController < ApplicationController
      def register
        user = User.new(user_params)
        user.role = 'user'
        if user.save
          render json: { token: user.api_token, email: user.email, role: user.role }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def login
        user = User.find_for_database_authentication(email: params.require(:email))
        if user&.valid_password?(params.require(:password))
          user.regenerate_api_token
          render json: { token: user.api_token, email: user.email, role: user.role }
        else
          render json: { error: 'Invalid email or password' }, status: :unauthorized
        end
      end

      private

      def user_params
        params.permit(:email, :password, :password_confirmation)
      end
    end
  end
end
