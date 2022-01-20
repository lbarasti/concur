require "./spec_helper"

describe Future do
  it "runs a computation asyncronously" do
    ch = Channel(Nil).new
    
    Future.new { ch.send nil }

    ch.receive
  end

  it "can be awaited on" do
    f = Future.new { 2** 10 }
    res = f.await
    res.should eq 1024
    typeof(res).should eq (Int32 | Exception)
  end

  it "can be awaited on multiple times" do
    f = Future.new { 2** 10 }
    10.times { 
      f.await.should eq 1024
    }
  end

  it "can be awaited on by multiple fibers" do
    n_fibers = 100
    results = Channel(Int32 | Exception).new(n_fibers)
    f = Future.new { sleep rand; 2** 10 }
    n_fibers.times { 
      spawn {
        results.send f.await
      }
    }
    n_fibers.times {
      results.receive.should eq 1024
    }
  end

  it "can be awaited on and raise on exception" do
    f = Future.new { sleep 0.4; raise CustomError.new("error"); 42 }
    expect_raises(CustomError) {
      f.await!
    }
  end

  it "can be awaited on with timeout" do
    f = Future.new { sleep 0.6; 42 }
    f.await(0.2.seconds)
      .should be_a Future::Timeout
    f.await
      .should eq 42
    f.await(0.1.seconds)
      .should eq 42
  end

  it "can be awaited on with timeout and raise on exception" do
    f = Future.new { sleep 0.4; raise CustomError.new("error"); 42 }
    expect_raises(Future::Timeout) {
      f.await!(0.2.seconds)
    }
    expect_raises(CustomError) {
      f.await!(0.3.seconds)
    }
  end

  it "can be queried for completion" do
    f = Future.new { sleep 0.3; :done }
    f.done?.should be_false
    f.await
    f.done?.should be_true
  end

  it "supports running callbacks, in order, on completion" do
    results = [] of Int32
    f = Future.new { 5 }
    f.on_complete { |r|
      results << r.as(Int32) + 1
      raise Exception.new("runtime exception")
    }.on_complete { |r|
      case r
      when Int32
        results << r
      end
    }.await.should eq 5

    results.should eq [6, 5]
  end

  it "supports running callbacks in order on success" do
    results = [] of Int32
    f = Future.new { 5 }
    f.on_success { |r|
      results << r.as(Int32) + 1
      raise Exception.new("runtime exception")
    }.on_success { |r|
      case r
      when Int32
        results << r
      end
    }.await.should eq 5

    results.should eq [6, 5]
  end

  it "will not run #on_success callbacks if the future fails" do
    results = [] of Int32
    f = Future.new { raise CustomError.new; 5 }
    f.on_success { |r|
      results << 1
    }.on_success { |r|
      raise Exception.new
      results << 2
    }.await.should be_a CustomError

    results.should be_empty
  end

  it "supports running callbacks in order on error" do
    results = [] of Exception
    f = Future.new { raise CustomError.new; 5 }

    f.on_error { |ex|
      results << ex.as(CustomError)
      raise Exception.new("runtime exception")
    }.on_error { |ex|
      results << Future::Timeout.new
    }.await.should be_a CustomError

    results.first.should be_a CustomError
    results.last.should be_a Future::Timeout
  end

  it "will not run #on_error callbacks if the future succeeds" do
    results = [] of Int32
    f = Future.new { 5 }
    f.on_error { |r|
      results << 1
    }.on_error { |r|
      raise Exception.new
      results << 2
    }.await.should eq 5

    results.should be_empty
end

  it "supports function composition" do
    c_1 = Future.new { rand ** 2 }
    c_2 = c_1.map { |x| 1 - x }
    
    (c_1.await! + c_2.await!).should eq 1
    c_2.done?.should be_true
  end

  it "doesn't propagate errors backward when composing functions" do
    c_1 = Future.new { 2 }
    c_2 = c_1.map { |x| raise CustomError.new("error"); 1 - x }
    
    c_2.await.should be_a CustomError
    c_1.await.should eq 2
  end

  it "propagates errors when composing functions" do
    c_1 = Future.new { raise CustomError.new("error"); rand ** 2 }
    c_2 = c_1.map { |x| raise Exception.new("generic error"); 1 - x }
    
    c_2.await.should be_a CustomError
  end

  it "can be filtered" do
    f = Future.new { 5 }
    g = f.select { |x| x % 2 == 1 }
    h = f.select { |x| x % 2 == 0 }
    g.await.should eq 5
    h.await.should be_a Future::EmptyError
  end

  it "supports combining two futures with #flat_map" do
    f = Future.new { 5 }
    g = Future.new { 3 }
    
    f.flat_map { |x| g.map { |y| x + y } }
      .await.should eq 8
  end

  it "will return the first encountered error on #flat_map" do
    f = Future.new { raise CustomError.new; 5 }
    g = Future.new { 3 }
    
    f.flat_map { |x| g.map { |y| x + y } }
      .await.should be_a CustomError
  end

  it "can be flattened in case of nested futures" do
    f = Future.new { Future.new { 5 } }
    f.await.should be_a Future(Int32)
    
    f.flatten
      .await.should eq 5
  end

  it "supports mapping its underlying value to a specific type" do
    f = Future.new { rand < 0.5 ? "hello" : 5 }
    
    typeof(f.await).should eq String | Int32 | Exception
    v = f.map_to(Int32).await
    typeof(v).should eq Int32 | Exception
  end

  it "raises a TypeCastError when mapping to an incompatible type" do
    f = Future.new { rand < 0.5 ? "hello" : 5 }
    g = f.map { |v| v.class == Int32 ? "hello 2" : 6 }

    expect_raises(TypeCastError) {
      fv = f.map_to(Int32).await!
      gv = g.map_to(Int32).await!
    }
  end

  it "can be recovered if it fails" do
    f = Future.new { raise CustomError.new; 42 }
    f.recover { |e|
      case e
      when CustomError
        100
      else
        raise Exception.new("Unexpected failure")
      end
    }.await.should eq 100
  end

  it "does not recover successful futures" do
    f = Future.new { 42 }
    f.recover { |ex| 43 }
      .await.should eq 42
  end

  it "can be transformed" do
    f = Future.new { 42 }
    g = Future.new { raise CustomError.new; 42 }
    t = -> (res : Int32 | Exception) {
      case res
      when Int32
        "#{res + 1}"
      else
        "0"
      end
    }
    f.transform(&t).await.should eq "43"
    g.transform(&t).await.should eq "0"
  end

  it "supports zipping futures together" do
    f = Future.new { 1 }
    g = Future.new { 2 }
    f.zip(g) { |v1, v2| v1 + v2 }
      .await.should eq 3
  end
end
