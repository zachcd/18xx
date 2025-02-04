# frozen_string_literal: true

require_relative '../../../step/buy_train'
require_relative '../skip_coal_and_oil'

module Engine
  module Game
    module G1868WY
      module Step
        class BuyTrain < Engine::Step::BuyTrain
          include G1868WY::SkipCoalAndOil

          def process_buy_train(action)
            super
            action.train.remove_variants!
          end
        end
      end
    end
  end
end
