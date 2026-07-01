# frozen_string_literal: true

RSpec.describe Plumbing::Provider::Router do
  subject(:router) { described_class.new }

  describe "register" do
    it "returns a route describing a static route" do
      route = router.register "some/path"

      expect(route).to be_static
      expect(route).to_not be_dynamic
      expect(route.path).to eq "some/path"
      expect(route.params).to be_empty
    end

    it "strips leading and trailing slashes" do
      leading = router.register "/leading/slash"
      trailing = router.register "trailing/slash/"
      both = router.register "/both/slashes/"

      expect(leading.path).to eq "leading/slash"
      expect(trailing.path).to eq "trailing/slash"
      expect(both.path).to eq "both/slashes"
    end

    it "returns a route describing a dynamic route" do
      route = router.register "say/:something/to/:someone"

      expect(route).to be_dynamic
      expect(route).to_not be_static
      expect(route.path).to eq "say/:something/to/:someone"
      expect(route.params[1]).to eq :something
      expect(route.params[3]).to eq :someone
    end
  end

  describe "query" do
    it "raises InvalidPath if the route has not been registered" do
      expect { router.query "some/path" }.to raise_error Plumbing::Provider::Router::InvalidPath
    end

    it "returns a query for a static route" do
      route = router.register "static"
      query = router.query "static"

      expect(query.route).to eq route
      expect(query.params).to be_empty
    end

    it "returns a query for a dynamic route" do
      route = router.register "hello/:name"
      query = router.query "hello/alice"

      expect(query.route).to eq route
      expect(query.params).to eq({name: "alice"})
    end

    it "prioritises routes with the most static segments" do
      two_dynamic = router.register "say/:something/to/:someone"
      one_dynamic = router.register "say/:something/to/alice"
      static = router.register "say/hello/to/alice"

      expect(router.query("say/goodbye/to/bob").route).to eq two_dynamic
      expect(router.query("say/goodbye/to/alice").route).to eq one_dynamic
      expect(router.query("say/hello/to/alice").route).to eq static
    end

    it "does not match routes with no matching static segments" do
      router.register "hello/:name"
      expect { router.query("goodbye/alice") }.to raise_error Plumbing::Provider::Router::InvalidPath
    end

    it "strips leading and trailing slashes when locating a static route" do
      route = router.register "static"

      query = router.query "/static"
      expect(query.route).to eq route

      query = router.query "static/"
      expect(query.route).to eq route

      query = router.query "/static/"
      expect(query.route).to eq route
    end
  end

  describe "dynamic routes" do
    it "generates the segments from the path" do
      @route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@route.segments).to eq ["first", "second", ":third", ":fourth"]
    end

    it "generates the params with their positions" do
      @route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@route.params[2]).to eq :third
      expect(@route.params[3]).to eq :fourth
    end

    it "generates the static segments with their positions" do
      @route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@route.statics[0]).to eq "first"
      expect(@route.statics[1]).to eq "second"
    end

    it "has zero matches when the length of the path is different to the route's path" do
      @route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@route.matches_for("first/second/third/fourth/fifth")).to eq 0
    end

    it "has zero matches when the static segments do not match" do
      @route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@route.matches_for("fifth/sixth/seventh/eighth")).to eq 0
      expect(@route.matches_for("second/first/third/fourth")).to eq 0
    end

    it "returns the number of static segments that match" do
      @no_params = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/third/fourth")
      @one_param = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/third/:fourth")
      @two_params = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")

      expect(@no_params.matches_for("first/second/third/fourth")).to eq 4
      expect(@one_param.matches_for("first/second/third/fourth")).to eq 3
      expect(@two_params.matches_for("first/second/third/fourth")).to eq 2
    end
  end

  describe "querys" do
    it "generates a key from the provided route" do
      route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")
      query = Plumbing::Provider::Router::Query.new(route: route, path: "first/second/third/fourth")

      expect(query.key).to eq route.path
    end

    it "generates segments from the provided path" do
      route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")
      query = Plumbing::Provider::Router::Query.new(route: route, path: "first/second/third/fourth")

      expect(query.segments).to eq ["first", "second", "third", "fourth"]
    end

    it "generates params from the route and path" do
      route = Plumbing::Provider::Router::DynamicRoute.new(path: "first/second/:third/:fourth")
      query = Plumbing::Provider::Router::Query.new(route: route, path: "first/second/third/fourth")

      expect(query.params).to eq({third: "third", fourth: "fourth"})
    end
  end
end
