-module(shopping_cart).
-compile(export_all).
-include_lib("n2o/include/wf.hrl").
-include_lib("kvs/include/products.hrl").
-include_lib("kvs/include/users.hrl").
-include_lib("kvs/include/groups.hrl").
-include_lib("kvs/include/feeds.hrl").
-include_lib("feed_server/include/records.hrl").
-include("records.hrl").

main() -> #dtl{file="prod", bindings=[{title,<<"shopping cart">>},{body, body()}]}.

body()-> index:header() ++ [
    #section{class=[section], body=[
        #panel{class=[container], body=[
            #panel{class=["row-fluid"], body=[
            case wf:user() of undefined -> wf:redirect("/login");
            User -> [
                #panel{class=[span9], body=[
                    case lists:keyfind(cart, 1, element(#iterator.feeds, User)) of false -> [];
                    {_, CId} ->
                        State = ?CART_STATE(CId),
                        #feed_ui{title= <<"shopping cart">>,
                            icon="icon-shopping-cart icon-large blue",
                            selection_ctl=checkout_ctl(State),
                            state=State,
                            header=#panel{class=["btn-toolbar"], body=[
                                #link{class=?BTN_INFO, body= <<"continune shopping">>, url="/store"}]}} end,
                    #panel{class=["hero-unit", "clearfix"], body= <<"">>},
                    case lists:keyfind(wishlist, 1, element(#iterator.feeds, User)) of false -> [];
                    {_, WId} ->
                        #feed_ui{title= <<"whish list">>,
                            icon="icon-list blue",
                            state=?CART_STATE(WId)#feed_state{view=store},
                            header=[]} end]},

                #panel{class=[span3], body=[
                    #h3{class=["text-center"],body=#span{class=["text-warning"],body= <<"Order Summary">>}},
                    #panel{id=?USR_ORDER(User#user.id), body=order_summary()}]} ] end ]}]}]}] ++ index:footer().

order_summary() -> order_summary(undefined).
order_summary(S)->
    {Items, Total} = order_products(S),
    #panel{class=["well","pricing-table", "product-price", "text-center"], body=[
        Items,
        #h3{body= <<"Estimated total: ">>},
        #h3{class=["pricing-table-price", "product-price-price"], body=[
            #span{class=["icon-usd"]}, float_to_list(Total/100, [{decimals, 2}]) ]},
        #link{class=[btn, "btn-warning"], body= <<"checkout">>, postback={checkout, S}}
    ]}.

order_products(#feed_state{selected_key=Selected, visible_key=Visible})->
    Selection = sets:from_list(wf:session(Selected)),
    Products = lists:flatten([case kvs:get(product,Pid) of {error,_}->[];{ok, P}-> P end
        || {Pid,_}=Id <- wf:session(Visible), sets:is_element(wf:to_list(erlang:phash2(Id)), Selection)]),

    lists:mapfoldl(fun(#product{}=P, In)-> {
        [#h4{body=P#product.title},
         #list{class=["pricing-table-list", "product-price-list", unstyled], body=[
            #li{body= [#span{class=["icon-usd"]},
                float_to_list(P#product.price/100, [{decimals, 2}])]}]}],
        In+P#product.price} end, 0, Products);
order_products(undefined)-> {<<"">>, 0}.

cart_item(P, State) ->
    Id = wf:to_list(erlang:phash2(element(State#feed_state.entry_id, P))),
    wf:render([
        #panel{id=?EN_MEDIA(Id), class=[span4, "media-pic"], style="margin:0;",
            body=#entry_media{media=media(P#product.cover), mode=store}},

        #panel{class=[span5, "article-text"], body=[
            #h3{body=#span{id=?EN_TITLE(Id), class=[title], body=
                #link{style="color:#9b9c9e;", body=P#product.title, postback={read, product, P#product.id}}}},

            #p{id=?EN_DESC(Id), body=product_ui:shorten(P#product.brief)} ]},

        #panel{class=[span3, "text-center"], body=[
            #h3{style="",
                body=[#span{class=["icon-usd"]}, float_to_list(P#product.price/100, [{decimals, 2}]) ]},
                #link{class=?BTN_INFO, body= <<"to wishlist">>, postback={to_wishlist, P, State}}
        ]} ]).

checkout_ctl(State) -> [
    #link{id=?FD_CHKOUT(State#feed_state.container_id),
        class=[btn, "btn-warning"], body= <<"checkout">>,
        data_fields=?TOOLTIP, title= <<"checkout">>,
        postback={checkout, State},
        delegate=shopping_cart},
    #link{class=?BTN_INFO, body= <<"to wishlist">>,
        data_fields=?TOOLTIP, title= <<"wishlist">>,
        postback={to_wishlist, State},
        delegate=shopping_cart}].

%% Render shopping cart elements

render_element(#div_entry{entry=#entry{}=E, state=#feed_state{view=cart}=State}) ->
    case kvs:get(product, E#entry.entry_id) of
        {ok, P} -> cart_item(P, State);
        {error,_}-> <<"item not available">> end;
render_element(#div_entry{entry=#product{}=P, state=#feed_state{view=cart}=State}) ->
    cart_item(P, State);
render_element(E)-> store:render_element(E).

event(init) -> wf:reg(?MAIN_CH),[];
event({delivery, [_|Route], Msg}) -> process_delivery(Route, Msg);
event({read, product, Id})-> wf:redirect("/product?id="++Id);
event({select, Sel, #feed_state{view=cart}=S})->
    User = wf:user(),
    feed_ui:event({select, Sel, S}),
    wf:update(?USR_ORDER(User#user.id), order_summary(S));

event({to_wishlist, #product{}=P, #feed_state{}=S})->
    User = wf:user(),
    Fid = S#feed_state.container_id,
    Fs = ?FD_STATE(Fid, S)#feed_state{view=store},
    Is = #input_state{
        collect_msg = false,
        show_recipients = false,
        entry_type = wishlist,
        entry_id = P#product.id,
        title = P#product.title,
        description = P#product.brief,
        medias=[media(P#product.cover)]},
    error_logger:info_msg("Input ~p ~p", [P#product.id, Fid]),
    input:event({post, wishlist, Is, Fs}),
    msg:notify( [kvs_feed, user, User#user.email, entry, Fid, delete],
                [#entry{id={P#product.id, Fid}, entry_id=P#product.id, feed_id=Fid}, Is, Fs]);

event({to_wishlist, #feed_state{selected_key=Selected, visible_key=Visible}=S})->
    Selection = sets:from_list(wf:session(Selected)),
    User = wf:user(),
    case lists:keyfind(wishlist, 1, User#user.feeds) of false -> ok;
    {_,Fid} -> Is = #input_state{},
        [case kvs:get(entry, Id) of {error,_} -> ok; 
        {ok, E} ->
            msg:notify( [kvs_feed, user, User#user.email, entry, Eid, add],
                        [E#entry{id={Eid, Fid}, feed_id=Fid}, Is, ?FD_STATE(Fid, S)#feed_state{view=store}]),

            msg:notify( [kvs_feed, user, User#user.email, entry, FeedId, delete],
                        [E, Is, ?FD_STATE(S)#feed_state{view=store}])
        end || {Eid,FeedId}=Id <- wf:session(Visible), sets:is_element(wf:to_list(erlang:phash2(Id)), Selection)] end;

event({add_cart, #product{}=P, #feed_state{}=S}=M) ->
    store:event(M),
    User = wf:user(),
    case lists:keyfind(wishlist, 1, User#user.feeds) of false -> ok;
    {_,Fid} -> msg:notify([kvs_feed, user, User#user.email, entry, Fid, delete],
                          [#entry{id={P#product.id, Fid}, entry_id=P#product.id, feed_id=Fid}, #input_state{}, S]) end;

event({checkout, #feed_state{selected_key=Selected, visible_key=Visible}}) ->
    wf:redirect("/checkout?sid="++Selected++"&vid="++Visible);

event(E) -> feed_ui:event(E).

process_delivery([_,_,_,_,add]=R,
                 [E, #input_state{}=I, #feed_state{}=S]=M)->
    User = wf:user(),
    wf:update(?USR_ORDER(User#user.id), order_summary(S)),
    feed_ui:process_delivery(R,M);
process_delivery(R,M) -> feed_ui:process_delivery(R,M).

media(undefined)-> #media{};
media(File)-> #media{url = File,
    thumbnail_url = filename:join([filename:dirname(File),"thumbnail",filename:basename(File)])}.

short_date(undefined) -> short_date(now());
short_date(Date) ->
    {{Y, M, D}, {_,_,_}} = calendar:now_to_datetime(Date),
    io_lib:format("~s ~p, ~p", [?MONTH(M), D, Y]).
