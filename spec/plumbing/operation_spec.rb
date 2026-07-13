# frozen_string_literal: true

require "plumbing/actor/threaded"

RSpec.describe Plumbing::Operation do
  context "state definitions" do
    describe "startup" do
      it "moves to the first state" do
        no_op_class = Class.new(Plumbing::Operation) do
          result :done
        end

        no_op = no_op_class.start
        expect(no_op).to be_in :done
      end

      it "initialises then moves to the first state" do
        starting_class = Class.new(Plumbing::Operation) do
          prop :am_i_ready, _Boolean, default: false, reader: true

          starts_with do
            @am_i_ready = true
          end

          result :done
        end

        starter = starting_class.start
        expect(starter.am_i_ready.await).to be true
      end
    end

    describe "actions" do
      it "is called then moves to the next state" do
        counter_class = Class.new(Plumbing::Operation) do
          prop :value, _Integer, default: 0, reader: true

          action :increment do
            @value += 1
          end
          go_to :done

          result :done
        end

        counter = counter_class.start
        expect(counter.value.await).to eq 1
      end
    end

    describe "decisions" do
      it "is evaluated then moves to the matching state" do
        is_it_the_weekend_class = Class.new(Plumbing::Operation) do
          prop :day, String, default: "Mon"

          decision :what_day_is_it? do
            go_to :weekday, if: -> { %w[Mon Tue Wed Thu Fri].include? @day }
            go_to :weekend, if: -> { %w[Sat Sun].include? @day }
          end

          result :weekday
          result :weekend
        end

        is_it_the_weekend = is_it_the_weekend_class.start day: "Mon"
        expect(is_it_the_weekend).to be_in :weekday

        is_it_the_weekend = is_it_the_weekend_class.start day: "Sat"
        expect(is_it_the_weekend).to be_in :weekend

        is_it_the_weekend = is_it_the_weekend_class.start(day: "November")
        expect(is_it_the_weekend).to be_failed
        expect(is_it_the_weekend.exception.await).to be_kind_of Plumbing::Operation::NoDecision
      end
    end

    describe "waiting and interactions" do
      before do
        Plumbing::Actor.uses :threaded
      end

      after do
        Plumbing::Actor.uses :inline
      end

      it "waits until a condition is met" do
        Sync do
          is_it_the_weekend_class = Class.new(Plumbing::Operation) do
            prop :day, String, default: ""

            wait_until :day_is_valid? do
              go_to :weekday, if: -> { %w[Mon Tue Wed Thu Fri].include? @day }
              go_to :weekend, if: -> { %w[Sat Sun].include? @day }
            end

            interaction :it_is do
              param :day, String
              calls do |day:|
                @day = day
              end
            end

            result :weekday
            result :weekend
          end

          is_it_the_weekend = is_it_the_weekend_class.start

          sleep 0.1
          expect(is_it_the_weekend).to be_in :day_is_valid?
          sleep 0.1

          await { is_it_the_weekend.it_is day: "Mon" }
          expect(is_it_the_weekend).to be_in :weekday
        end
      end

      it "raises an error if a non-deferrable worker-type is used" do
        Plumbing::Actor.uses :inline

        test_class = Class.new(Plumbing::Operation) do
          prop :done, _Boolean, default: false

          wait_until :something_has_happened? do
            go_to :done, if: -> { @dome }
          end
        end

        expect { test_class.start }.to raise_error Plumbing::Actor::NotSupported
      end
    end

    describe "results" do
      it "defines an end state" do
        no_op_class = Class.new(Plumbing::Operation) do
          result :done
        end

        no_op = no_op_class.start
        expect(no_op).to be_completed
        expect(no_op).to be_in :done
      end
    end
  end
end
