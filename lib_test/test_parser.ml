(*
 * Copyright (c) 2012 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open OUnit
open Printf

let basic_req =
"GET /index.html HTTP/1.1\r\nHost: www.example.com\r\n\r\n"

let basic_res =
"HTTP/1.1 200 OK
Date: Mon, 23 May 2005 22:38:34 GMT
Server: Apache/1.3.3.7 (Unix) (Red-Hat/Linux)
Last-Modified: Wed, 08 Jan 2003 23:11:55 GMT
Etag: \"3f80f-1b6-3e1cb03b\"
Accept-Ranges:  none
Content-Length: 0
Connection: close
Content-Type: text/html; charset=UTF-8"

let basic_res_content =
"HTTP/1.1 200 OK
Date: Mon, 23 May 2005 22:38:34 GMT
Server: Apache/1.3.3.7 (Unix) (Red-Hat/Linux)
Last-Modified: Wed, 08 Jan 2003 23:11:55 GMT
Etag: \"3f80f-1b6-3e1cb03b\"
Accept-Ranges:  none
Content-Length: 32
Connection: close
Content-Type: text/html; charset=UTF-8

home=Cosby&favorite+flavor=flies"

let post_req =
"POST /path/script.cgi HTTP/1.0
From: frog@jmarshall.com
User-Agent: HTTPTool/1.0
Content-Type: application/x-www-form-urlencoded
Content-Length: 32

home=Cosby&favorite+flavor=flies"

let post_data_req =
"POST /path/script.cgi HTTP/1.0
From: frog@jmarshall.com
User-Agent: HTTPTool/1.0
Content-Length: 32

home=Cosby&favorite+flavor=flies"

let post_chunked_req =
"POST /foo HTTP/1.1
Date: Fri, 31 Dec 1999 23:59:59 GMT
Content-Type: text/plain
Transfer-Encoding: chunked

1a; ignore-stuff-here
abcdefghijklmnopqrstuvwxyz
10
1234567890abcdef
0
some-footer: some-value
another-footer: another-value

"

let chunked_res =
"HTTP/1.1 200 OK
Date: Fri, 31 Dec 1999 23:59:59 GMT
Content-Type: text/plain
Transfer-Encoding: chunked

1a; ignore-stuff-here
abcdefghijklmnopqrstuvwxyz
10
1234567890abcdef
0
some-footer: some-value
another-footer: another-value

"

let basic_res_plus_crlf = basic_res ^ "\r\n\r\n"

module Cohttp = Cohttp_lwt

let basic_req_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string basic_req) in
  Parser.parse_request_fst_line ic >>=
  function
  |Some (meth, uri, ver) ->
    assert_equal ver `HTTP_1_1;
    assert_equal meth `GET;
    assert_equal (Uri.to_string uri) "/index.html";
    return ()
  |None -> assert false

let basic_res_parse res () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string res) in
  Parser.parse_response_fst_line ic >>=
  function
  |Some (version, status) ->
     (* Parse first line *)
     assert_equal version `HTTP_1_1;
     assert_equal status `OK;
     (* Now parse the headers *)
     Parser.parse_headers ic >>= fun headers ->
     assert_equal (List.assoc "connection" headers) "close";
     assert_equal (List.assoc "accept-ranges" headers) "none";
     assert_equal (List.assoc "content-type" headers) "text/html; charset=UTF-8";
     return ()
  |None -> assert false

let req_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string basic_req) in
  Request.parse ic >>= function
  |None -> assert false
  |Some req ->
    assert_equal `GET (Request.meth req);
    assert_equal "/index.html" (Request.path req);
    assert_equal `HTTP_1_1 (Request.version req);
    return ()

let post_form_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string post_req) in
  Request.parse ic >>= function
  |None -> assert false
  |Some req ->
    assert_equal (Some "Cosby") (Request.param "home" req);
    assert_equal (Some "flies") (Request.param "favorite flavor" req);
    assert_equal None (Request.param "nonexistent" req);
    (* multiple requests should still work *)
    assert_equal (Some "Cosby") (Request.param "home" req);
    return ()

let post_data_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string post_data_req) in
  Request.parse ic >>= function
  |None -> assert false
  |Some req ->
    Request.body req >>= fun body ->
    assert_equal (Some "home=Cosby&favorite+flavor=flies") body;
    (* A subsequent request for the body will have consumed it, therefore None *)
    Request.body req >>= fun body ->
    assert_equal None body;
    return ()

let post_chunked_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string post_chunked_req) in
  Request.parse ic >>= function
  |None -> assert false
  |Some req ->
    assert_equal (Request.transfer_encoding req) "chunked";
    Request.body req >>= fun chunk ->
    assert_equal chunk (Some "abcdefghijklmnopqrstuvwxyz");
    Request.body req >>= fun chunk ->
    assert_equal chunk (Some "1234567890abcdef");
    return ()

let res_content_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string basic_res_content) in
  Response.parse ic >>= function
  |None -> assert false
  |Some res ->
     assert_equal `HTTP_1_1 (Response.version res);
     assert_equal `OK (Response.status res);
     Response.body res >>= fun body ->
     assert_equal (Some "home=Cosby&favorite+flavor=flies") body;
     return ()

 let res_chunked_parse () =
  let open Cohttp in
  let open IO in
  let ic = ic_of_buffer (Lwt_bytes.of_string chunked_res) in
  Response.parse ic >>= function
  |None -> assert false
  |Some res ->
     assert_equal `HTTP_1_1 (Response.version res);
     assert_equal `OK (Response.status res);
     Response.body res >>= fun chunk ->
     assert_equal chunk (Some "abcdefghijklmnopqrstuvwxyz");
     Response.body res >>= fun chunk ->
     assert_equal chunk (Some "1234567890abcdef");
     return ()
  
let test_cases =
  let tests = [ basic_req_parse; req_parse; post_form_parse; post_data_parse; 
    post_chunked_parse; (basic_res_parse basic_res); (basic_res_parse basic_res_plus_crlf);
    res_content_parse ] in
  List.map (fun x -> "test" >:: (fun () -> Lwt_unix.run (x ()))) tests

(* Returns true if the result list contains successes only.
   Copied from oUnit source as it isnt exposed by the mli *)
let rec was_successful =
  function
    | [] -> true
    | RSuccess _::t
    | RSkip _::t ->
        was_successful t
    | RFailure _::_
    | RError _::_
    | RTodo _::_ ->
        false

let _ =
  let suite = "Parser" >::: test_cases in
  let verbose = ref false in
  let set_verbose _ = verbose := true in
  Arg.parse
    [("-verbose", Arg.Unit set_verbose, "Run the test in verbose mode.");]
    (fun x -> raise (Arg.Bad ("Bad argument : " ^ x)))
    ("Usage: " ^ Sys.argv.(0) ^ " [-verbose]");
  if not (was_successful (run_test_tt ~verbose:!verbose suite)) then
  exit 1
