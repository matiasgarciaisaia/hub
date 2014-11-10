describe VerboiceConnector do
  describe "initialization" do
    it "should set defaults for new connector" do
      connector = VerboiceConnector.make
      expect(connector.url).to eq("https://verboice.instedd.org")
      expect(connector.shared).to eq(false)
    end
  end

  context "basic auth" do
    let(:connector) { VerboiceConnector.new username: 'jdoe', password: '1234', shared: false }
    let(:user) { User.make }

    describe "lookup" do
      let(:url_proc) { ->(path) { "http://server/#{path}" }}

      it "finds root" do
        expect(connector.lookup [], user).to be(connector)
      end

      it "reflects on root" do
        expect(connector.reflect(url_proc, user)).to eq({
          properties: {
            "projects" => {
              label: "Projects",
              type: :entity_set,
              path: "projects",
              reflect_url: "http://server/projects"
            }
          }
        })
      end

      it "lists projects" do
        stub_request(:get, "https://jdoe:1234@verboice.instedd.org/api/projects.json").
          to_return(status: 200, body: %([
            {
              "id": 495,
              "name": "my project",
              "call_flows": [{
                "id": 740,
                "name": "my flow"}],
              "schedules": []
            }]), headers: {})

        projects = connector.lookup(%w(projects), user)
        expect(projects.reflect(url_proc, user)).to eq({
          entities: [
            {
              label: "my project",
              path: "projects/495",
              reflect_url: "http://server/projects/495"
            }
          ]
        })
      end

      it "reflects on project" do
        projects = connector.lookup %w(projects 495), user
        expect(projects.reflect(url_proc, user)).to eq({
          properties: {
            "id" => {
              label: "Id",
              type: :integer
            },
            "name" => {
              label: "Name",
              type: :string
            },
            "call_flows" => {
              label: "Call flows",
              type: :entity_set,
              path: "projects/495/call_flows",
              reflect_url: "http://server/projects/495/call_flows",
            },
          },
          actions: {
            "call"=> {
              label: "Call",
              path: "projects/495/$actions/call",
              reflect_url: "http://server/projects/495/$actions/call"
            }
          }
        })
      end

      it "reflects on project call flows" do
        stub_request(:get, "https://jdoe:1234@verboice.instedd.org/api/projects/495.json").
         to_return(:status => 200, :body => %({
            "id": 495,
            "name": "my project",
            "call_flows": [{
              "id": 740,
              "name": "my flow"}],
            "schedules": []
          }), :headers => {})

        call_flows = connector.lookup %w(projects 495 call_flows), user
        expect(call_flows.reflect(url_proc, user)).to eq({
          entities: [{
            label: "my flow",
            path: "projects/495/call_flows/740",
            reflect_url: "http://server/projects/495/call_flows/740",
          }],
        })
      end

      it "reflects on call flow" do
        call_flow = connector.lookup %w(projects 495 call_flows 740), user
        expect(call_flow.reflect(url_proc, user)).to eq({
          events: {
            "call_finished" => {
              label: "Call finished",
              path: "projects/495/call_flows/740/$events/call_finished",
              reflect_url: "http://server/projects/495/call_flows/740/$events/call_finished"
            }
          }
        })
      end

      it "reflects on call flow call finished event" do
        stub_request(:get, "https://jdoe:1234@verboice.instedd.org/api/projects/740.json").
          to_return(:status => 200, :body => %({"contact_vars":["name","age"]}), :headers => {})

        event = connector.lookup %w(projects 495 call_flows 740 $events call_finished), user
        expect(event.reflect(url_proc, user)).to eq({
          label: "Call finished",
          args: {
            "name" => :string,
            "age" => :string,
          }
        })
      end

      it "reflects on call" do
        projects = connector.lookup %w(projects 495 $actions call), user
        expect(projects.reflect(url_proc)).to eq({
          label:"Call",
          args: {
            channel: {
              type: "string",
              label: "Channel"},
            number: {
              type: "string",
              label:"Number"
            }
          }
        })
      end
    end

    describe "call" do
      it "invokes" do
        stub_request(:get, "https://jdoe:1234@verboice.instedd.org/api/call?address=&channel=Channel").
         to_return(:status => 200, :body => %({"call_id":755961,"state":"queued"}), :headers => {})

        projects = connector.lookup %w(projects 495 $actions call), user

        response = projects.invoke({'channel' => 'Channel', 'address' => '123'}, user)
        expect(response).to eq({
          "call_id" => 755961,
          "state" => "queued"
        })
      end
    end
  end

  context "guisso with shared connectors" do
    let(:connector) { VerboiceConnector.new shared: true }
    let(:user) { User.make }

    before(:each) do
      allow(Guisso).to receive_messages(
        enabled?: true,
        url: "http://guisso.com",
        client_id: "12345",
        client_secret: "12345"
      )

      stub_request(:post, "http://guisso.com/oauth2/token").
        with(:body => {"grant_type"=>"client_credentials", "scope"=>"app=verboice.instedd.org user=#{user.email}"}).
        to_return(:status => 200, :body => '{
          "token_type": "Bearer",
          "access_token": "This is a guisso auth token!",
          "expires_in": 7200
          }', :headers => {})
    end

    describe "lookup" do
      let(:url_proc) { ->(path) { "http://server/#{path}" }}

      it "finds root" do
        expect(connector.lookup [], user).to be(connector)
      end

      it "reflects on root" do
        expect(connector.reflect(url_proc, user)).to eq({
          properties: {
            "projects" => {
              label: "Projects",
              type: :entity_set,
              path: "projects",
              reflect_url: "http://server/projects"
            }
          }
        })
      end

      it "lists projects" do
        stub_request(:get, "https://verboice.instedd.org/api/projects.json").
          with(:headers => {'Authorization'=>'Bearer This is a guisso auth token!'}).
          to_return(status: 200, body: %([
            {
              "id": 495,
              "name": "my project",
              "call_flows": [{
                "id": 740,
                "name": "my flow"}],
              "schedules": []
            }]), headers: {})

        projects = connector.lookup(%w(projects), user)
        expect(projects.reflect(url_proc, user)).to eq({
          entities: [
            {
              label: "my project",
              path: "projects/495",
              reflect_url: "http://server/projects/495"
            }
          ]
        })
      end

      it "reflects on project" do
        projects = connector.lookup %w(projects 495), user
        expect(projects.reflect(url_proc, user)).to eq({
          properties: {
            "id" => {
              label: "Id",
              type: :integer
            },
            "name" => {
              label: "Name",
              type: :string
            },
            "call_flows" => {
              label: "Call flows",
              type: :entity_set,
              path: "projects/495/call_flows",
              reflect_url: "http://server/projects/495/call_flows",
            },
          },
          actions: {
            "call"=> {
              label: "Call",
              path: "projects/495/$actions/call",
              reflect_url: "http://server/projects/495/$actions/call"
            }
          }
        })
      end

      it "reflects on call" do
        projects = connector.lookup %w(projects 495 $actions call), user
        expect(projects.reflect(url_proc)).to eq({
          label:"Call",
          args: {
            channel: {
              type: "string",
              label: "Channel"},
            number: {
              type: "string",
              label:"Number"
            }
          }
        })
      end
    end

    describe "call" do
      it "invokes" do
        stub_request(:get, "https://verboice.instedd.org/api/call?address=&channel=Channel").
          with(:headers => {'Authorization'=>'Bearer This is a guisso auth token!'}).
          to_return(:status => 200, :body => %({"call_id":755961,"state":"queued"}), :headers => {})

        projects = connector.lookup %w(projects 495 $actions call), user

        response = projects.invoke({'channel' => 'Channel', 'address' => '123'}, user)
        expect(response).to eq({
          "call_id" => 755961,
          "state" => "queued"
        })
      end
    end
  end


end
