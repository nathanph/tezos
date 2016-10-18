open Data_encoding
open Context
open Hash

let (>>=) = Lwt.bind
let (>|=) = Lwt.(>|=)
let (//) = Filename.concat

let write_file dir ~name content =
  let file = (dir // name) in
  let oc = open_out file in
  output_string oc content ;
  close_out oc ;
  file

let is_invalid_arg = function
  | Invalid_argument _ -> true
  | _ -> false

let test_simple_json ?msg ?eq:(equal=Assert.equal) encoding value =
    let json = Json.construct encoding value in
    let result = Json.destruct encoding json in
    equal ?msg value result

let test_simple_bin ?msg ?(equal=Assert.equal) encoding value =
  let bin = Binary.to_bytes encoding value in
  let opt = Binary.of_bytes encoding bin in
  Assert.is_some ?msg opt;
  let result = match opt with None -> assert false | Some v -> v in
  equal ?msg value result

let test_json_exn ?msg ?(equal=Assert.equal) encoding value fail =
  let get_result () =
    let bin = Json.construct encoding value in
    Json.destruct encoding bin in
  Assert.test_fail ?msg get_result fail

let test_bin_exn ?msg ?(equal=Assert.equal) encoding value fail =
  let get_result () =
    let bin = Binary.to_bytes encoding value in
    Binary.of_bytes encoding bin in
  Assert.test_fail ?msg get_result fail

let test_simple ~msg enc value =
  test_simple_json ~msg:(msg ^ ": json") enc value ;
  test_simple_bin ~msg:(msg ^ ": binary") enc value

let test_simple_int ~msg ?(boundary=true) encoding i =
  let pow y = int_of_float @@ (2. ** float_of_int y) in
  let i = i - 1 in
  let range_min = - pow i in
  let range_max = pow i - 1 in
  let out_max = pow i in
  let out_min = - pow i - 1 in
  test_simple ~msg encoding range_min ;
  test_simple ~msg encoding range_max ;
  if boundary then begin
    test_simple_bin ~msg ~equal:(Assert.not_equal) encoding out_max ;
    test_simple_bin ~msg ~equal:(Assert.not_equal) encoding out_min
  end


let test_simple_values _ =
  test_simple ~msg:__LOC__ null ();
  test_simple ~msg:__LOC__ empty ();
  test_simple ~msg:__LOC__ (constant "toto") ();
  test_simple_int ~msg:__LOC__ int8 8;
  test_simple_int ~msg:__LOC__ int16 16;
  test_simple_int ~msg:__LOC__ ~boundary:false int31 31;
  test_simple ~msg:__LOC__ int32 Int32.min_int;
  test_simple ~msg:__LOC__ int32 Int32.max_int;
  test_simple ~msg:__LOC__ int64 Int64.min_int;
  test_simple ~msg:__LOC__ int64 Int64.max_int;
  test_simple ~msg:__LOC__ bool true;
  test_simple ~msg:__LOC__ bool false;
  test_simple ~msg:__LOC__ string "tutu";
  test_simple ~msg:__LOC__ bytes (MBytes.of_string "titi");
  test_simple ~msg:__LOC__ float 42.;
  test_simple ~msg:__LOC__ (option string) (Some "thing");
  test_simple ~msg:__LOC__ (option string) None;
  let enum_enc =
    ["one", 1; "two", 2; "three", 3; "four", 4; "five", 6; "six", 6] in
  test_simple_bin ~msg:__LOC__ (string_enum enum_enc) 4;
  test_json_exn ~msg:__LOC__ (string_enum enum_enc) 7 is_invalid_arg ;
  test_bin_exn ~msg:__LOC__ (string_enum enum_enc) 7
    (function
      | No_case_matched -> true
      | _ -> false) ;
  (* Should fail *)
  (* test_bin_exn ~msg:__LOC__ (string_enum ["a", 1; "a", 2]) 2 (...duplicatate...); *)
  (* test_json_exn ~msg:__LOC__ (string_enum ["a", 1; "a", 2]) 1 (... duplicate...); *)

  Lwt.return_unit

let test_json testdir =
  let file = testdir // "testing_data_encoding.tezos" in
  let v = `Float 42. in
  let f_str = Json.to_string v in
  Assert.equal_string  ~msg:__LOC__ f_str "[\n  42\n]";
  Json.read_file (testdir // "NONEXISTINGFILE") >>= fun rf ->
  Assert.is_none ~msg:__LOC__ rf;
  Json.write_file file v >>= fun success ->
  Assert.is_true ~msg:__LOC__ success;
  Json.read_file file >>= fun opt ->
  Assert.is_some ~msg:__LOC__ opt;
  Lwt.return ()

type t = A of int | B of string | C of int | D of string | E

let prn_t = function
  | A i -> Printf.sprintf "A %d" i
  | B s -> Printf.sprintf "B %s" s
  | C i -> Printf.sprintf "C %d" i
  | D s -> Printf.sprintf "D %s" s
  | E -> "E"

let test_tag_errors _ =
    let duplicate_tag () =
      union [
        case ~tag:1
          int8
          (fun i -> i)
          (fun i -> Some i) ;
        case ~tag:1
          int8
          (fun i -> i)
          (fun i -> Some i)] in
    Assert.test_fail ~msg:__LOC__ duplicate_tag
      (function Duplicated_tag _ -> true
              | _ -> false) ;
    let invalid_tag () =
      union [
        case ~tag:(2 lsl 7)
          int8
          (fun i -> i)
          (fun i -> Some i)] in
    Assert.test_fail ~msg:__LOC__  invalid_tag
      (function (Invalid_tag (_, `Int8)) -> true
              | _ -> false) ;
    Lwt.return_unit

let test_union _ =
  let enc =
    (union [
        case ~tag:1
          int8
          (function A i -> Some i | _ -> None)
          (fun i -> A i) ;
        case ~tag:2
          string
          (function B s -> Some s | _ -> None)
          (fun s -> B s) ;
        case ~tag:3
          int8
          (function C i -> Some i | _ -> None)
          (fun i -> C i) ;
        case ~tag:4
          (obj2
             (req "kind" (constant "D"))
             (req "data" (string)))
          (function D s -> Some ((), s) | _ -> None)
          (fun ((), s) -> D s) ;
      ]) in
  let jsonA = Json.construct enc (A 1) in
  let jsonB = Json.construct enc (B "2") in
  let jsonC = Json.construct enc (C 3) in
  let jsonD = Json.construct enc (D"4") in
  Assert.test_fail
    ~msg:__LOC__ (fun () -> Json.construct enc E) is_invalid_arg ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (A 1) (Json.destruct enc jsonA) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (B "2") (Json.destruct enc jsonB) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (A 3) (Json.destruct enc jsonC) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (D "4") (Json.destruct enc jsonD) ;
  let binA = Binary.to_bytes enc (A 1) in
  let binB = Binary.to_bytes enc (B "2") in
  let binC = Binary.to_bytes enc (C 3) in
  let binD = Binary.to_bytes enc (D "4") in
  Assert.test_fail ~msg:__LOC__ (fun () -> Binary.to_bytes enc E)
    (function
      | No_case_matched -> true
      | _ -> false) ;
  let get_result ~msg bin =
    match Binary.of_bytes enc bin with
    | None -> Assert.fail_msg "%s" msg
    | Some bin -> bin in
  Assert.equal ~prn:prn_t ~msg:__LOC__ (A 1) (get_result ~msg:__LOC__ binA) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (B "2") (get_result ~msg:__LOC__ binB) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (C 3) (get_result ~msg:__LOC__ binC) ;
  Assert.equal ~prn:prn_t ~msg:__LOC__ (D "4") (get_result ~msg:__LOC__ binD) ;
  Lwt.return_unit


type s = { field : int }

let test_splitted _ =
  let s_enc =
    def "s" @@
    describe
      ~title:"testsuite encoding test"
      ~description: "A human readable description" @@
    conv
      (fun s -> string_of_int s.field)
      (fun s -> { field = int_of_string s })
      string in
  let enc =
    (splitted
       ~binary:string
       ~json:
         (union [
             case ~tag:1
               string
               (fun _ -> None)
               (fun s -> s) ;
             case ~tag:2
               s_enc
               (fun s -> Some { field = int_of_string s })
              (fun s -> string_of_int s.field) ;
           ])) in
  let get_result ~msg bin =
    match Binary.of_bytes enc bin with
    | None -> Assert.fail_msg "%s: Cannot parse." msg
    | Some bin -> bin in
  let jsonA = Json.construct enc "41" in
  let jsonB = Json.construct s_enc {field = 42} in
  let binA = Binary.to_bytes enc "43" in
  let binB = Binary.to_bytes s_enc {field = 44} in
  Assert.equal ~msg:__LOC__ "41" (Json.destruct enc jsonA);
  Assert.equal ~msg:__LOC__ "42" (Json.destruct enc jsonB);
  Assert.equal ~msg:__LOC__ "43" (get_result ~msg:__LOC__ binA);
  Assert.equal ~msg:__LOC__ "44" (get_result ~msg:__LOC__ binB);
  Lwt.return_unit

let test_json_input testdir =
  let enc =
    obj1
      (req "menu" (
          obj3
            (req "id" string)
            (req "value" string)
            (opt "popup" (
                obj2
                  (req "width" int64)
                  (req "height" int64))))) in
  begin
    let file =
      write_file testdir ~name:"good.json" {|
 {
    "menu": {
        "id": "file",
        "value": "File",
        "popup": {
            "width" : 42,
            "height" : 52
        }
    }
}
|}
    in
    Json.read_file file >>= function
      None -> Assert.fail_msg "Cannot parse \"good.json\"."
    | Some json ->
        let (id, value, popup) = Json.destruct enc json in
        Assert.equal_string ~msg:__LOC__ "file" id;
        Assert.equal_string ~msg:__LOC__ "File" value;
        Assert.is_some ~msg:__LOC__ popup;
        let w,h = match popup with None -> assert false | Some (w,h) -> w,h in
        Assert.equal_int64 ~msg:__LOC__ 42L w;
        Assert.equal_int64 ~msg:__LOC__ 52L h;
        Lwt.return_unit
  end >>= fun () ->
  let enc =
    obj2
      (req "kind" (string))
      (req "data" (int64)) in
  begin
    let file =
      write_file testdir ~name:"unknown.json" {|
{
  "kind" : "int64",
  "data" : "42",
  "unknown" : 2
}
|}
    in
    Json.read_file file >>= function
      None -> Assert.fail_msg "Cannot parse \"unknown.json\"."
    | Some json ->
        Assert.test_fail ~msg:__LOC__
          (fun () -> ignore (Json.destruct enc json))
          (function
            | Json.Unexpected_field "unknown" -> true
            | _ -> false) ;
        Lwt.return_unit
  end

let tests = [
  "simple", test_simple_values ;
  "json", test_json ;
  "union", test_union ;
  "splitted", test_splitted ;
  "json.input", test_json_input ;
  "tags", test_tag_errors ;
]

let () =
  Test.run "data_encoding." tests