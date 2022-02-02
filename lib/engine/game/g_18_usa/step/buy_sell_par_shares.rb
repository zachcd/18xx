# frozen_string_literal: true

require_relative '../../g_1817/step/buy_sell_par_shares'

module Engine
  module Game
    module G18USA
      module Step
        class BuySellParShares < G1817::Step::BuySellParShares
          MIN_BID = 100
          MAX_BID = 100_000
          MAX_PAR_PRICE = 200

          def auto_actions(entity)
            return [Engine::Action::Pass.new(entity)] if @auctioning && max_bid(entity, @auctioning) < min_bid(@auctioning)

            []
          end

          def min_increment
            1
          end

          def must_bid_increment_multiple?
            false
          end

          def validate_bid(entity, corporation, bid)
            max_bid = max_bid(entity, corporation)
            raise GameError, "Invalid bid, maximum bidding power is #{max_bid}" if bid > max_bid
          end

          def max_bid(entity, corporation = nil)
            super + (corporation&.tokens&.first&.used ? city_subsidy(corporation)&.value || 0 : max_city_subsidy)
          end

          def max_city_subsidy
            @game.subsidies_by_hex.values.map { |s| s[:value] }.max || 0
          end

          def add_bid(action)
            unless @auctioning
              bid = action.price
              max_bid = @game.bidding_power(action.entity)
              @round.needed_city_subsidy = bid - max_bid if bid > max_bid
            end

            super
          end

          def win_bid(winner, _company)
            super

            entity = winner.entity
            corporation = winner.corporation

            # Corporation only gets share price * 2 in cash, not the full winning bid
            extra_cash = corporation.cash - (corporation.share_price.price * 2)
            corporation.spend(extra_cash, @game.bank) if extra_cash.positive?

            subsidy = city_subsidy(corporation)
            return unless subsidy

            @game.log << "Subsidy contributes #{@game.format_currency(subsidy.value)}"
            @game.bank.spend(subsidy.value, entity)
            subsidy.close!
          end

          def par_price(bid)
            par_price = super
            [par_price, self.class::MAX_PAR_PRICE].min
          end

          def transfer_subsidy_ownership(to, subsidy)
            from = subsidy.owner
            subsidy.owner = to
            from.companies.delete(subsidy)
            to.companies << subsidy
          end

          def city_subsidy(corporation)
            corporation.companies.find { |c| c.value.positive? }
          end

          def available_subsidiaries(entity)
            entity ||= current_entity
            return [] if !@winning_bid || @winning_bid.entity != entity

            entity.companies
          end

          def process_assign(action)
            company = action.target
            corporation = @winning_bid.corporation
            price = @winning_bid.price

            current_value = corporation.companies.sum(&:value)
            if current_value + company.value > price
              raise GameError, 'Total company contributions cannot exceed winning bid. ' \
                               "#{@game.format_currency(price - current_value)} remaining."
            end

            if company.id == 'P29' && corporation.companies.any? { |c| c.name == 'No Subsidy' }
              @game.log << "#{corporation.name} immediately gets a free 2 train and #{company.name} closes"
              @game.buy_train(corporation, @game.depot.depot_trains.first, :free)
              company.close!
            end

            corporation_hex = corporation.tokens.first.hex
            if company.id == 'P10' && @game.potential_metropolitan_hexes.include?(corporation_hex) &&
                !@game.active_metropolitan_hexes.include?(corporation_hex)
              @game.log << "#{company.name} turns #{corporation_hex.location_name} into a metropolis"
              @game.convert_potential_metro(corporation_hex)
              @game.graph.clear
            end

            super

            @game.bank.spend(corporation.cash.abs, corporation) if corporation.cash.negative?
          end

          def contribution_can_exceed_corporation_cash?
            true
          end

          def handle_plus_ten(subsidy_company)
            subsidy_company.owner.tokens.first.hex.tile.icons << Engine::Part::Icon.new('18_usa/plus_ten', sticky: true)
            subsidy_company.close!
          end

          def handle_plus_ten_twenty(subsidy_company)
            subsidy_company.owner.tokens.first.hex.tile.icons << Engine::Part::Icon.new('18_usa/plus_ten_twenty', sticky: true)
            subsidy_company.close!
          end

          def par_corporation
            return unless @corporation_size

            corporation = @winning_bid.corporation

            corporation.companies.dup.each do |c|
              case c.name
              when 'No Subsidy'
                c.close!
              when '+10'
                handle_plus_ten(c)
              when '+10 / +20'
                handle_plus_ten_twenty(c)
              end
            end

            if corporation.tokens.first.hex.id == 'E11' && @game.metro_denver
              @round.pending_tracks << {
                entity: corporation,
                hexes: [corporation.tokens.first.hex],
              }
            end

            super
          end
        end
      end
    end
  end
end
