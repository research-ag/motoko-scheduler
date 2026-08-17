import Bench "mo:bench-helper";

module {
  public func init() : Bench.V1 {
    let schema : Bench.Schema = {
      name = "My benchmark name";
      description = "My description";
      rows = ["bench1"];
      cols = ["val0"];
    };

    let run : Bench.Runner = func(ri, ci) {
      // benchmark code...
    };

    Bench.V1(schema, run);
  };
};
