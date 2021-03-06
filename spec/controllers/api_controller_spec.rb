describe ApiController do
  describe 'elasticsearch connector' do
    let(:connector) { ElasticsearchConnector.make! }
    let(:user)      { connector.user }
    before          { sign_in user }

    describe "entity set data api" do
      let(:entity_properties) { { "foo" => "bar" } }
      let(:duck_context) { duck_type(:user, :data_url, :reflect_url) }

      it 'should be able to query with empty filter' do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:query).and_return({items: []})

        get :query, id: connector.guid, path: "indices/my_index/types/patients", filter: "" # filter: "" mimics ?filter=
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to eq({"items" => []})
      end

      it "should be able to insert into an entity set" do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:insert).with(entity_properties, duck_context)

        post :insert, id: connector.guid, path: "indices/my_index/types/patients", properties: entity_properties
        expect(response.status).to eq(200)
      end

      it "should be able to update elements of an entity set" do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:update).with({}, entity_properties, duck_context)

        put :update, id: connector.guid, path: "indices/my_index/types/patients", properties: entity_properties
        expect(response.status).to eq(200)
      end

      it "should create elements if none where updated and create_or_update is set" do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:update).and_return(0)
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:insert).with(entity_properties, duck_context)

        put :update, id: connector.guid, path: "indices/my_index/types/patients",\
                                           properties: entity_properties,\
                                           create_or_update: "true"
        expect(response.status).to eq(200)
      end

      it "should not create elements if none where updated and create_or_update is not set" do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:update).and_return(0)
        expect_any_instance_of(ElasticsearchConnector::Type).not_to receive(:insert)

        put :update, id: connector.guid, path: "indices/my_index/types/patients", properties: entity_properties
        expect(response.status).to eq(200)
      end

      it "should be able to delete elements of an entity set" do
        expect_any_instance_of(ElasticsearchConnector::Type).to receive(:delete).with({}, duck_context)

        delete :delete, id: connector.guid, path: "indices/my_index/types/patients"
        expect(response.status).to eq(200)
      end
    end
  end

  describe 'verboice events' do
    let!(:verboice_connector) { VerboiceConnector.make! user: nil }
    let!(:token) { verboice_connector.generate_secret_token! }

    it 'should validate authenticity token' do
      request.env["RAW_POST_DATA"] = "{}"
      request.headers["X-InSTEDD-Hub-Token"] = "#{token}_invalid"

      post :notify, id: verboice_connector.guid, path: "projects/1/call_flows/6/$events/call_finished"
      expect(response.status).to eq(401)
    end

    it "should enqueue a NotifyJob" do
      data = {"project_id"=>1, "call_flow_id"=>6, "address"=>"17772632588", "vars"=>{"age"=>"20"}}.to_json
      request.env["RAW_POST_DATA"] = data
      request.headers["X-InSTEDD-Hub-Token"] = token
      path = "projects/1/call_flows/6/$events/call_finished"

      expect(Resque).to receive(:enqueue_to).with(:hub, Connector::NotifyJob, verboice_connector.id, path, data)

      post :notify, id: verboice_connector.guid, path: path
    end

    it "should not fail if raw post data is empty" do
      request.env["RAW_POST_DATA"] = nil
      request.headers["X-InSTEDD-Hub-Token"] = token
      path = "projects/1/call_flows/6/$events/call_finished"

      expect(Resque).to receive(:enqueue_to).with(:hub, Connector::NotifyJob, verboice_connector.id, path, "{}")

      post :notify, id: verboice_connector.guid, path: path
    end

    it "should route fine with paths with periods" do
      request.env["RAW_POST_DATA"] = nil
      request.headers["X-InSTEDD-Hub-Token"] = token
      path = "route/6/$events/call_finished.path"

      expect(:post => "/api/notify/connectors/#{verboice_connector.guid}/#{path}").to route_to(
        :controller => "api",
        :action => 'notify',
        :id => "#{verboice_connector.guid}",
        :path => "#{path}"
      )
    end
  end

  describe "query and invoke" do
    def url
      "http://localhost:9200"
    end

    def index_url
      "#{url}/instedd_hub_test"
    end

    let(:connector) { ElasticsearchConnector.make! url: url }
    let(:user)      { connector.user }
    before(:each)   { sign_in user }

    before(:each) do
      RestClient.delete index_url rescue nil
      RestClient.post index_url, %(
        {
          "mappings": {
            "type1": {
              "properties": {
                  "name": { "type" : "string" },
                  "age":  { "type" : "integer" },
                  "other": { "type" : "string" }
              }
            }
          }
        }
      )
    end

    after(:all) do
      RestClient.delete index_url rescue nil
    end

    it "queries elastic search" do
      RestClient.post("#{index_url}/type1", %({"name": "john", "age": 20}))
      RestClient.post("#{index_url}/type1", %({"name": "peter", "age": 40}))
      RestClient.post("#{index_url}/type1", %({"name": "martin", "age": 30}))
      RestClient.post "#{index_url}/_refresh", ""

      allow(ElasticsearchConnector).to receive(:default_page_size).and_return(2)

      get :query, id: connector.guid, path: "indices/instedd_hub_test/types/type1"

      result = JSON.parse(response.body)
      expect(result["items"].length).to eq(2)
      expect(result["next_page"]).to eq("http://test.host/api/data/connectors/#{connector.guid}/indices/instedd_hub_test/types/type1?page=2")
    end

    it "updates elastic search values (with null values)" do
      RestClient.post("#{index_url}/type1", %({"name": "john", "age": 20, "other": 50}))
      RestClient.post("#{index_url}/type1", %({"name": "peter", "age": 40, "other": 60}))
      RestClient.post "#{index_url}/_refresh", ""

      request.env["RAW_POST_DATA"] = %({
        "filters": {
          "name": "john",
          "age": null
        },
        "properties": {
          "name": "john",
          "age": 10,
          "other": null
        }
      })
      post :invoke, id: connector.guid, path: "indices/instedd_hub_test/types/type1/$actions/update"

      RestClient.post "#{index_url}/_refresh", ""

      response = JSON.parse RestClient.get "#{index_url}/_search"
      hits = response["hits"]["hits"]
      expect(hits.length).to eq(2)

      sources = hits.map { |hit| hit["_source"] }

      john = sources.find { |source| source["name"] == "john" }
      expect(john["age"]).to eq(10)
      expect(john["other"]).to eq(50)

      peter = sources.find { |source| source["name"] == "peter" }
      expect(peter["age"]).to eq(40)
      expect(peter["other"]).to eq(60)
    end

    it "updates elastic search values (with empty string values)" do
      RestClient.post("#{index_url}/type1", %({"name": "john", "age": 20, "other": 50}))
      RestClient.post("#{index_url}/type1", %({"name": "peter", "age": 40, "other": 60}))
      RestClient.post "#{index_url}/_refresh", ""

      request.env["RAW_POST_DATA"] = %({
        "filters": {
          "name": "john",
          "age": ""
        },
        "properties": {
          "name": "john",
          "age": 10,
          "other": ""
        }
      })
      post :invoke, id: connector.guid, path: "indices/instedd_hub_test/types/type1/$actions/update"

      RestClient.post "#{index_url}/_refresh", ""

      response = JSON.parse RestClient.get "#{index_url}/_search"
      hits = response["hits"]["hits"]
      expect(hits.length).to eq(2)

      sources = hits.map { |hit| hit["_source"] }

      john = sources.find { |source| source["name"] == "john" }
      expect(john["age"]).to eq(10)
      expect(john["other"]).to eq(50)

      peter = sources.find { |source| source["name"] == "peter" }
      expect(peter["age"]).to eq(40)
      expect(peter["other"]).to eq(60)
    end
  end
end
