describe RapidProConnector do
  describe "new run event" do
    let!(:connector) { RapidProConnector.make! }

    let(:event) {
      connector.lookup_path "flows/12345/$events/run_update", nil
    }

    it "triggers on new runs with variables" do
      events = event.process_runs_response [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [
            {
              "label" => "fever",
              "value" => "Yes",
              "time" => "2014-11-19T10:00:00.000Z"
            }
          ],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      expect(events).to eq([{
        "contact" => "contact-1-guid",
        "phone" => "+12345678",
        "values" => {
          "fever" => "Yes"
        }
      }])
    end

    it "shuould not trigger if no updates are present" do
      data = [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [
            {
              "label" => "fever",
              "value" => "Yes",
              "time" => "2014-11-19T10:00:00.000Z"
            }
          ],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      event.process_runs_response data
      events = event.process_runs_response data

      expect(events).to eq([])
    end

    it "triggers on updated runs with new the variables" do
      event.process_runs_response [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [
            {
              "label" => "fever",
              "value" => "Yes",
              "time" => "2014-11-19T10:00:00.000Z"
            }
          ],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      events = event.process_runs_response [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [
            {
              "label" => "fever",
              "value" => "Yes",
              "time" => "2014-11-19T10:00:00.000Z"
            },
            {
              "label" => "vomit",
              "value" => "No",
              "time" => "2014-11-19T11:00:00.000Z"
            }
          ],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      expect(events).to eq([{
        "contact" => "contact-1-guid",
        "phone" => "+12345678",
        "values" => {
          "fever" => "Yes",
          "vomit" => "No"
        }
      }])
    end

    it "run with no variables only once" do
      data = [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      events = event.process_runs_response data
      expect(events).to eq([{
        "contact" => "contact-1-guid",
        "phone" => "+12345678",
        "values" => {}
      }])

      events = event.process_runs_response data
      expect(events).to eq([])
    end

    it "should dismiss old events only" do
      data = [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [{
            "label" => "fever",
            "value" => "Yes",
            "time" => "2014-11-19T10:00:00.000Z"
          }],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      event.process_runs_response data

      data = [
        {
          "run" => 1,
          "phone" => "+12345678",
          "contact" => "contact-1-guid",
          "values" => [{
            "label" => "fever",
            "value" => "Yes",
            "time" => "2014-11-19T10:00:00.000Z"
          }],
          "created_on" => "2014-11-19T09:00:00.000Z"
        },
        {
          "run" => 2,
          "phone" => "+99999",
          "contact" => "contact-2-guid",
          "values" => [{
            "label" => "fever",
            "value" => "Yes",
            "time" => "2014-11-19T10:00:00.000Z"
          }],
          "created_on" => "2014-11-19T09:00:00.000Z"
        }
      ]

      events = event.process_runs_response data
      expect(events).to eq([{
        "contact" => "contact-2-guid",
        "phone" => "+99999",
        "values" => {"fever" => "Yes"}
      }])
    end
  end
end