-module(review).
-compile(export_all).
-include_lib("n2o/include/wf.hrl").
-include_lib("kvs/include/feeds.hrl").
-include_lib("kvs/include/users.hrl").
-include("records.hrl").

main() -> #dtl{file="dev", bindings=[{title,<<"review">>},{body, body()}]}.

body() ->
  index:header()++[
  #section{class=[section], body=#panel{class=[container], body=
    case kvs:all_by_index(entry, #entry.entry_id, case wf:qs(<<"id">>) of undefined -> -1; Id -> binary_to_list(Id) end) of [E|_] ->
      {{Y, M, D}, _} = calendar:now_to_datetime(E#entry.created),
      Date = io_lib:format(" ~p ~s ~p ", [D, element(M, {"Jan", "Feb", "Mar", "Apr", "May", "June", "July", "Aug", "Sept", "Oct", "Nov", "Dec"}), Y]),
      {From, Av} = case kvs:get(user, E#entry.from) of {ok, U} -> {U#user.display_name, U#user.avatar}; {error, _} -> {E#entry.from, <<"/static/holder.js/150x150">>} end,
      #panel{class=["row-fluid"], body=[
        #panel{class=[span3], body=[
          #panel{class=[sidebar], body=[
            #panel{id="review-meta", class=["row-fluid"], body=[
              #h3{class=["blue capital"], body= <<"action">>},
              #image{class=["img-polaroid"], alt= <<"The author">>, image=Av, width="150"},
              #p{class=[username], body= #link{body=From}},
              #p{class=[datestamp], body=[Date]},
              #p{class=[statistics], body=[
                  #link{body=[ #i{class=["icon-eye-open", "icon-large"]}, #span{class=[badge, "badge-info"], body= <<"1024">>} ], postback={read_entry, E#entry.id}},
                  #link{body=[ #i{class=["icon-comments-alt", "icon-large"]}, #span{class=[badge, "badge-info"], body= <<"10">>} ], postback={read_entry, E#entry.id}}
              ]},
              #panel{class=[], body=[
                  #link{url= <<"#">>, class=[btn, "btn-orange", capital], body= <<"Buy it!">>}
              ]}
            ]}
          ]}
        ]},
        #panel{class=[span9], body=[
          #product_entry{entry=E, mode=full}
        ]}
      ]};
      [] -> index:error(<<"not_found">>) end }},
  #section{class=[section], body=#panel{class=[container], body=[
    #h3{body= <<"more reviews">>, class=[blue, offset3]},
    #panel{class=["row-fluid"], body=more_article()}
  ]}}
  ]++index:footer().

more_article() ->
  #panel{class=["game-article","shadow-fix"], body=[
    #panel{class=["game-article-inner", clearfix], body=[
      #panel{class=[span3, "article-meta"], body=[
        #h3{class=[blue, capital], body= <<"Action">>},
        #p{class=[username], body= <<"John Smith">>}
        #p{class=[datestamp], body=[ <<"Yesterday">>, #span{body= <<"1:00pm">>}]},
        #p{class=[statistics], body=[
          #i{class=["icon-user"]},
          #span{body=[1,045]},
          #i{class=["icon-comment"]},
          #span{body= <<"25">>}
        ]}
      ]},
      #panel{class=[span3, shadow], body=#image{class=["border"], alt= <<"Row Four Image">>, image= <<"/static/img/row4.jpg">>}},
      #panel{class=[span6, "article-text"], body=[
        #h3{class=["light-grey"], body= <<"Lorem ipsum dolor sit amet">>},
        #p{body=[<<"Duis bibendum tortor at ligula condimentum sed dignissim elit tincidunt. Aliquam luctus ornare tortor ac hendrerit. Nam arcu odio, pretium et cursus nec, tempus ac massa. Nam eleifend quam eu justo adipiscing id eleifend tortor ullamcorper... ">>,
          #link{url= <<"#">>, body= <<"Read">>}
        ]}
      ]}
    ]}
  ]}.


event(init) -> wf:reg(product_channel),[];
event({delivery, [_|Route], Msg}) -> process_delivery(Route, Msg);
event({comment_entry, Eid, Cid, Csid})->
  Comment = wf:q(Cid),
  Medias = case wf:session(medias) of undefined -> []; L -> L end,
  User = wf:user(),
  Parent = undefined,
  error_logger:info_msg("Comment entry ~p:  ~p~n", [Eid, Cid]),
  msg:notify([kvs_feed, product, User#user.email, comment, product:uuid(), add], [User#user.email, Eid, Parent, Comment, Medias, Csid]);
event(Event) -> error_logger:info_msg("[review]event: ~p", [Event]), [].
api_event(Name,Tag,Term) -> error_logger:info_msg("[review]api_event ~p, Tag ~p, Term ~p",[Name,Tag,Term]).

process_delivery([_, _Owner, comment, Cid, add],
                 [From, Eid, Parent, Content, Medias, Csid])->
  error_logger:info_msg("update the fucking entry comments ~p ~p~n", [Eid, Cid]),
  wf:insert_bottom(Csid, #entry_comment{comment=#comment{id={Cid, Eid}, entry_id=Eid, comment_id=Cid, content=Content, media=Medias, parent=Parent, author_id=From, creation_time=erlang:now()}});

process_delivery(_R, _M) -> skip.