return function(api)
 local w=api.scene();local c=w.chests[1];local p=api.player()
 p.body.x=c.rect.x+8;p.body.y=c.rect.y+22;p.facing='up'
 w.sstate.chests[c.obj.props.flag]=nil
 w:interact()
 api.check(w.dialogue.open and c.open_t==0,'opening chest starts reward dialogue')
 api.wait(30)
 api.check(c.open_t and c.open_t>=.32,'chest animation completes while dialogue is open')
 local n=api.state().inventory[c.obj.props.item]
 api.talk_through();w:interact()
 api.check(api.state().inventory[c.obj.props.item]==n,'opening again does not duplicate reward')
end
