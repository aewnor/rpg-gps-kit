-- Visual timing only: never changes combat windows, collisions or saved state.
local M={reduced=false,system=false,user=false}
function M.set(source,value) M[source]=value;M.reduced=M.system or M.user end
function M.stride(distance) return math.floor(distance/8)%4 end
function M.bob(t,amount) return M.reduced and 0 or math.floor(math.sin(t)*(amount or 1)+.5) end
function M.ease(t) t=math.max(0,math.min(1,t));return 1-(1-t)^3 end
function M.chest_frame(t) return M.reduced and 5 or math.min(5,1+math.floor(M.ease(t/.32)*4)) end
function M.chest_tier(tier,key)
 local h=0;for i=1,#key do h=(h*31+key:byte(i))%65521 end
 if tier=='wood' then return ({'wood','sea','forest'})[h%3+1] end
 if tier=='iron' and h%2==0 then return 'roman' end
 if tier=='silver' and h%3==1 then return 'crystal' end
 return tier
end
function M.attack(t,w)
 if t<w.windup then return -.7*M.ease(t/w.windup) end
 if t<w.windup+w.active then return -.7+2*M.ease((t-w.windup)/w.active) end
 return 1.3*(1-M.ease((t-w.windup-w.active)/w.recovery))
end
return M
