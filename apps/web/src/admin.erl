-module(admin).
-compile(export_all).
-include_lib("n2o/include/wf.hrl").
-include_lib("kvs/include/products.hrl").
-include_lib("kvs/include/users.hrl").
-include_lib("kvs/include/acls.hrl").
-include_lib("kvs/include/groups.hrl").
-include_lib("kvs/include/feeds.hrl").
-include_lib("feed_server/include/records.hrl").
-include("records.hrl").

main()-> #dtl{file="prod", bindings=[{title,<<"admin">>},{body, body()}]}.

body() ->
    wf:wire(#api{name=tabshow}),
    wf:wire("$('a[data-toggle=\"tab\"]').on('shown', function(e){tabshow($(e.target).attr('href'));});"),
    Tab = case wf:qs(<<"tab">>) of undefined -> <<"categories">>; T ->  T end,
    wf:wire(io_lib:format("$(document).ready(function(){$('a[href=\"#~s\"]').tab('show');});",[Tab])),

    Nav = {wf:user(), admin, subnav()},
    index:header() ++ dashboard:page(Nav, [
        #panel{class=[span9, "tab-content"], style="min-height:400px;", body=[
            #panel{id=Id, class=["tab-pane"]} || Id <-[categories, acl, users, products] ]} ]) ++ index:footer().

tab(categories) ->
    State = ?FD_STATE(?GRP_FEED)#feed_state{entry_type=group, enable_selection=true, enable_traverse=true, html_tag=table},
    Is = #input_state{show_recipients=false, show_scope=true, show_media=false, entry_type=group},
    [
    #input{state=Is, feed_state=State, title= <<"Add category">>, placeholder_ttl= <<"name">>, icon="icon-tags"},
    #feed_ui{
        title= <<"Categories ">>,
        icon="icon-list", state=State,

        header=[#tr{class=["feed-table-header"], cells=[
            #th{body= <<"">>},
            #th{body= <<"id">>},
            #th{body= <<"name">>},
            #th{body= <<"description">>},
            #th{body= <<"scope">>} ]} 
        ]} 
    ];

tab(acl)-> {AclEn, Acl} = acls(), [
    dashboard:section(acl(Acl), "icon-male"),
    #panel{class=["tab-content"], body=[AclEn]}
    ];
tab(users) ->
    State = ?FD_STATE(?USR_FEED)#feed_state{entry_type=user, entry_id=#user.username, html_tag=table},
    #feed_ui{title= <<"Users ">>, icon="icon-user", state=State,
        header=[#tr{class=["feed-table-header"], cells=[
        #th{body= <<"email">>},
        #th{body= <<"roles">>},
        #th{body= <<"last login">>}]} ]};
tab(products)->
    State = ?FD_STATE(?PRD_FEED)#feed_state{entry_type=product, enable_selection=true, html_tag=table},
    #feed_ui{title= <<"Products">>, icon="icon-gamepad", state=State,
        header=[#tr{class=["feed-table-header"], cells=[#th{body= <<"">>},#th{body= <<"title">>}, #th{}]}]};

tab(_)-> [].

subnav() -> [
    {categories, "categories"},
    {acl, "acl"},
    {users, "users"},
    {products, "products"}
  ].

resources()->[
  #h3{class=[blue], body= <<"Resources">>},
  #table{class=[table, "table-hover"], body=[[
      #tr{cells=[#td{body= <<"category">>}]},
      #tr{cells=[#td{body= <<"user">>}]},
      #tr{cells=[#td{body= <<"product">>}]},
      #tr{cells=[#td{body= <<"feed">>}]}
      #tr{cells=[#td{body= <<"feature">>}]}
    ]]}
  ].

acl(Rows)->[
  #h3{class=[blue], body= <<"ACL">>},
  #table{class=[table, "table-hover"], header=[#tr{cells=[#th{body= <<"id">>}, #th{body= <<"resourse">>}]}], body=[Rows]}].

acls()->
    lists:mapfoldl(fun(#acl{id={R,N}=Aid}, Ain) ->
        State = #feed_state{container=acl, container_id=Aid, entry_type=acl_entry, html_tag=table},
        B = #panel{id=atom_to_list(R)++atom_to_list(N), class=["tab-pane"], body=[
            #feed_ui{title=wf:to_list(Aid)++" entries", icon="icon-list", state=State,
                header=[#tr{class=["feed-table-header"], cells=[
                    #th{body= <<"id">>},
                    #th{body= <<"accessor">>},
                    #th{body= <<"action">>}]} ]}]},
        Ao = [#tr{cells=[
            #td{body=#link{url="#"++atom_to_list(R)++atom_to_list(N), body=wf:to_list(Aid), data_fields=[{<<"data-toggle">>, <<"tab">>}]}}, 
            #td{body=wf:to_list(Aid)}]}|Ain],
        {B , Ao}
  end, [], kvs:all(acl)).

event(init) -> wf:reg(?MAIN_CH), [];
event({delivery, [_|Route], Msg}) -> process_delivery(Route, Msg);
event({view, Id}) -> error_logger:info_msg("redirect"), wf:redirect("/profile?id="++Id);
event({disable, What})-> error_logger:info_msg("ban user ~p", [What]);
event({revoke, Feature, Whom})->
  error_logger:info_msg("Disable ~p : ~p", [Whom, Feature]),
  User = wf:user(),
  case kvs:get(user, Whom) of {error, not_found} -> skip;
    {ok, U} ->
      kvs_acl:define_access({user, U#user.email}, {feature, Feature}, disable),

      ReplyRecipients = [{user, U#user.email, lists:keyfind(direct, 1, U#user.feeds)}],
      error_logger:info_msg("Reply recipients ~p", [ReplyRecipients]),
      EntryId = kvs:uuid(),
      [msg:notify([kvs_feed, RoutingType, To, entry, EntryId, add],
                  [#entry{id={EntryId, FeedId},
                          entry_id=EntryId,
                          feed_id=FeedId,
                          created = now(),
                          to = {RoutingType, To},
                          from=User#user.email,
                          type=reply,
                          media=[],
                          title= <<"Feature disabled">>,
                          description= "You role "++ io_lib:format("~p", [Feature])++" has been disabled!",
                          shared=""}, skip, skip, skip, direct]) || {RoutingType, To, {_, FeedId}} <- ReplyRecipients] end;

event(Event) -> error_logger:info_msg("Page event: ~p", [Event]), ok.

api_event(tabshow,Args,_) ->
    [Id|_] = string:tokens(Args,"\"#"),
    wf:update(list_to_atom(Id), tab(list_to_atom(Id)));
api_event(_,_,_) -> ok.

process_delivery(R,M) ->
    feed_ui:process_delivery(R,M).
