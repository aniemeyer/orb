#############################################################################
##
##  byorbits.gi              orb package                      
##                                                           Max Neunhoeffer
##                                                              Felix Noeske
##
##  Copyright 2005 Lehrstuhl D für Mathematik, RWTH Aachen
##
##  Implementation stuff for fast orbit enumeration by suborbits.
##
#############################################################################

###########################
# A few helper functions: #
###########################

InstallGlobalFunction( ORB_PrettyStringBigNumber,
function(n)
  local e,i,s;
  if n < 0 then
    e := "-";
    n := -n;
  else
    e := "";
  fi;
  s := String(n);
  i := 1;
  while i < Length(s) do
    Add(e,s[i]);
    if (Length(s)-i) mod 3 = 0 then
      Add(e,' ');
    fi;
    i := i + 1;
  od;
  Add(e,s[i]);
  return e;
end );

InstallGlobalFunction( ORB_InvWord, 
function(w)
  local wi,l,i;
  # Inverts w by changing the sign and reversing
  wi := ShallowCopy(w);
  l := Length(w);
  for i in [1..l] do
    wi[l+1-i] := - w[i];
  od;
  return wi;
end );

InstallGlobalFunction( ORB_ApplyWord, 
function(p,w,l,li,op)
  # p is a point, w is a word given as a list of small integers which are
  # indices in the list l or negatives of indices in the list li,
  # which is a list of group elements g, for which
  # op(p,g) is defined. 
  # Example: ORB_ApplyWord(p,[1,-2,3,2],[g1,g2,g3],[g1^-1,g2^-1,g3^-1],OnRight) 
  #          = p*g1*(g2^-1)*g3*g2
  local i;
  for i in w do
    if i < 0 then
      p := op(p,li[-i]);
    else
      p := op(p,l[i]);
    fi;
  od;
  return p;
end );

#########################
# Stabilizer Iterators: #
#########################

InstallMethod( StabIterator, "without arguments", [],  
  function( )
    local stab;
    stab := rec();
    Objectify( StdStabIteratorsType, stab );
    return stab;
  end );

InstallMethod( ViewObj, "for a stab iterator", 
  [ IsStabIterator and IsStdStabIteratorRep ],
  function( stab )
    if not(IsBound(stab!.i)) then
        Print("<newly born stab iterator>");
    else
        Print("<stabiterator size=",stab!.info," position=",stab!.pos,">");
    fi;
  end );

InstallMethod( Reset, "for a stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
function(stab)
  if not(IsBound(stab!.i)) then
      Error("StabIterator is not yet initialized");
      return;
  fi;
  stab!.pos := List(stab!.info,x->1);
  stab!.point := List([1..stab!.i],x->[]);
  stab!.cache := List([1..stab!.i],x->[]);
end );

InstallOtherMethod( Size, "for a std stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
  function( stab )
    return Product( stab!.info, Length );
  end );

InstallMethod( Next, "for a stab iterator",
  [ IsStabIterator and IsStdStabIteratorRep ],
function(stab)
  local i;
  i := 1;
  while true do
    if i > Length(stab!.pos) then
      return true;   # finished with this iterator
    fi;
    stab!.pos[i] := stab!.pos[i]+1;
    stab!.point[i] := [];    # this is no longer valid
    if stab!.pos[i] <= Length(stab!.info[i]) then
      return false;  # next element found
    fi;
    stab!.pos[i] := 1;
    i := i + 1;
  od;
  # this is never reached
end );

InstallGlobalFunction( ORB_ApplyStabElement,
function(p,j,i,setup,stab,w)
  local ww,www;
  while true do
    if i > 1 and IsBound(stab!.point[i][j]) and p = stab!.point[i][j] then
      if IsList(w) then Append(w,stab!.cache[i][j][1]); fi;
      p := stab!.cache[i][j][2];
    else
      stab!.point[i][j] := p;

      ww := ShallowCopy(setup!.trans[i][stab!.info[i][stab!.pos[i]]]);
      if IsList(w) then Append(w,ww); fi;
      p := ORB_ApplyWord(p,ww,setup!.els[j],setup!.elsinv[j],setup!.op[j]);
      if i = 1 then
        return p;
      fi;
      www := [];
      p := ORB_Minimalize(p,j,i,setup,false,www);
      Append(ww,www);
      if IsList(w) then Append(w,www); fi;

      stab!.cache[i][j] := [ww,p];
    fi;
    i := i - 1;
  od;
  # never comes here
end );


############################################
# The heart of the method: Minimalization: #
############################################

InstallMethod( ViewObj, "for an orbit-by-suborbit setup object",
  [ IsOrbitBySuborbitSetup ],
  function( setup )
    Print("<setup for an orbit-by-suborbit enumeration, k=",setup!.k,">");
  end );

InstallGlobalFunction( ORB_Minimalize,
function(p,j,i,setup,stab,w)
  # p is a point that should be minimalized. j is in 1..k+1 and indicates,
  # whether p is in P_j or in P (for j=k+1). i is in 1..k and indicates, 
  # which group U_i is used to minimalize. So only i <= j makes sense.
  # setup is a record describing the helper subgroups as defined above. 
  # Returns a U_i-minimal point q in the same U_i-orbit pU_i.
  # If stab is "false" nothing happens. If stab is a stabiterator object,
  # (usually will be "newly born" thus empty), that will
  # be filled with information for an iterator object for 
  # Stab_{U_i}(pi[j][i](q)) (see above).
  # If w is a list the word which is applied is appended.
  local m,minpoint,minstab,minstablen,minword,n,q,qq,qqq,ret,stablen,
        tempstab,v,vv,vvv,ww,www;
#Print("Mini:",j," ",i,"\n");
  if i = 1 then    # this is the smallest helper subgroup

    # go to P_1:
    if j > i then 
      q := setup!.pifunc[j][i](p,setup!.pi[j][i]); 
    else
      q := p;
    fi;
    v := ValueHT(setup!.info[i],q);
    if v = fail then    # we do not yet know this point
      ###Print("<\c");
      # we have to enumerate this U_1-orbit, apply all elements in trans:
      v := [];  # here we collect the stabilizer
      for m in [1..setup!.index[i]] do
        qq := ORB_ApplyWord(q,ORB_InvWord(setup!.trans[i][m]),
                        setup!.els[i],setup!.elsinv[i],setup!.op[i]);
        if q = qq then   # we found a stabilizer element:
          Add(v,m);
        else
          vv := ValueHT(setup!.info[i],qq);
          if vv = fail then    # we did not yet reach this point
            AddHT(setup!.info[i],qq,m);   # store this info
          fi;
        fi;
      od;
      AddHT(setup!.info[i],q,v);
      setup!.suborbnr[i] := setup!.suborbnr[i] + 1;
      setup!.sumstabl[i] := setup!.sumstabl[i] + Length(v);
      ###Print(Length(v),":",QuoInt(setup!.sumstabl[i],
      ###      setup!.suborbnr[i]),">   \r");

      # now p is by definition U_1-minimal
    else    # we already know this U_1-orbit:
      if IsInt(v) then   # this is the number of a word
        if IsList(w) then Append(w,setup!.trans[i][v]); fi;  # store what we do
        p := ORB_ApplyWord(p,setup!.trans[i][v],setup!.els[j],
                           setup!.elsinv[j],setup!.op[j]);
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi; # otherwise we are already U_1-minimal:
    fi;
    if IsStabIterator(stab) then
        stab!.i := 1;
        stab!.info := [v];
        stab!.pos := [1];
    fi;
#Print("Raus\n");
    return p;

  else   # we are in some higher helper subgroup than U_1:

    # first do a U_{i-1}-minimalization:
    p := ORB_Minimalize(p,j,i-1,setup,stab,w);

    # now try to reach the minimal U_{i-1}-suborbit in the U_i-orbit:
    if j > i then
      q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
    else
      q := p;
    fi;
    v := ValueHT(setup!.info[i],q);

    if v = fail then    # we do not yet know this U_{i-1}-suborbit

      ###Print("<",i,":\c");
      # first we apply all elements of the transversal of U_{i-1} in U_i,
      # U_{i-1}-minimalize them and search for the smallest stabilizer
      # to choose the U_i-minimal U_{i-1}-orbit:
      minpoint := fail;
      minword := fail;
      minstablen := -1;
      minstab := fail;
      for m in [1..setup!.index[i]] do
        tempstab := StabIterator();
        qq := ORB_ApplyWord(q,setup!.trans[i][m],setup!.els[i],
                            setup!.elsinv[i],setup!.op[i]);
        ww := ShallowCopy(setup!.trans[i][m]);
        qq := ORB_Minimalize(qq,i,i-1,setup,tempstab,ww);
        stablen := Product(tempstab!.info,Length);
        if minpoint = fail or stablen < minstablen then
          minpoint := qq;
          minstablen := stablen;
          minword := ww;
          minstab := tempstab;
        fi;
      od;
      # Now U_i-minimalize p:
      p := ORB_ApplyWord(p,minword,setup!.els[j],setup!.elsinv[j],setup!.op[j]);
      if IsList(w) then Append(w,minword); fi;
      q := minpoint;
      # in the second component we have to collect stabilizing transversal 
      # elements for subgroups U_1 to U_i:
      v := [true,List([1..i],x->[])];  
      AddHT(setup!.info[i],q,v);
                        
      # Now the U_{i-1}-orbit of the vector q is the U_i-minimal 
      # U_{i-1}-orbit and q is the U_i-minimal vector
      
      # first find all U_{i-1}-minimal elements in the U_i-minimal 
      # U_{i-1}-orbit:
      Reset(minstab);
      repeat
        ww := [];
        qq := ORB_ApplyStabElement(q,i,i-1,setup,minstab,ww);
        if qq <> q then   # some new U_{i-1}-minimal element?
          vv := ValueHT(setup!.info[i],qq);
          if vv = fail then
            AddHT(setup!.info[i],qq,[false,ORB_InvWord(ww)]);
          fi;
        else   # in this case this is an element of Stab_{U_{i-1}}(q) in P_i
          for n in [1..i-1] do
            AddSet(v[2][n],minstab!.info[n][minstab!.pos[n]]);
          od;
        fi;
      until Next(minstab);
      
      # we have to enumerate this U_i-orbit by U_{i-1}-orbits, storing
      # information for all U_{i-1}-minimal vectors:
      tempstab := StabIterator();
      for m in [1..setup!.index[i]] do
        # Apply t to find other U_{i-1}-orbits
        qq := ORB_ApplyWord(q,setup!.trans[i][m],setup!.els[i],
                            setup!.elsinv[i],setup!.op[i]);
        ww := ShallowCopy(setup!.trans[i][m]);
        qq := ORB_Minimalize(qq,i,i-1,setup,tempstab,ww);
        vv := ValueHT(setup!.info[i],qq);
        if vv <> fail and not(IsInt(vv)) then  
          # we are again in the U_i-minimal U_{i-1}-o.
          # then m has to go in the stabilizer info:
          Add(v[2][i],m);
        fi;
        if vv = fail then   # a new U_{i-1}-orbit
          # note that we now have stabilizer info in tempstab
          ret := setup!.cosetrecog[i](i,ORB_InvWord(ww),setup);
          AddHT(setup!.info[i],qq,ret);
          Reset(tempstab);
          repeat
            www := ShallowCopy(ww);
            qqq := ORB_ApplyStabElement(qq,i,i-1,setup,tempstab,www);
            vvv := ValueHT(setup!.info[i],qqq);
            if vvv = fail then
              ret := setup!.cosetrecog[i](i,ORB_InvWord(www),setup);
              AddHT(setup!.info[i],qqq,ret);
            fi;
          until Next(tempstab);
        fi;
      od;
      # now q is by definition the U_i-minimal point in the orbit and
      # v its setup!.info[i], i.e. [true,stabilizer information]
      setup!.suborbnr[i] := setup!.suborbnr[i] + 1;
      setup!.sumstabl[i] := setup!.sumstabl[i] + Product(v[2],Length);
      ###Print(Product(v[2],Length),":",
      ###      QuoInt(setup!.sumstabl[i],setup!.suborbnr[i]),">      \r");

    else   # we already knew this U_{i-1}-suborbit

      if IsInt(v) then    # this is the number of a word
        if IsList(w) then 
          Append(w,setup!.trans[i][v]);   # remember what we did
        fi;
        p := ORB_ApplyWord(p,setup!.trans[i][v],setup!.els[j],
                           setup!.elsinv[j],setup!.op[j]);
        # we again do a U_{i-1}-minimalization:
        p := ORB_Minimalize(p,j,i-1,setup,stab,w);
        # now we are in the U_i-minimal U_{i-1}-suborbit and on a 
        # U_{i-1}-minimal element
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi;
      if v[1] = false then    # not yet U_i-minimal 
        # we still have to apply an element of Stab_{U_{i-1}}(pi[j][i-1](p)):
        if IsList(w) then Append(w,v[2]); fi;  # remember what we did
        p := ORB_ApplyWord(p,v[2],setup!.els[j],setup!.elsinv[j],setup!.op[j]);
        if j > i then
          q := setup!.pifunc[j][i](p,setup!.pi[j][i]);
        else
          q := p;
        fi;
        v := ValueHT(setup!.info[i],q);
      fi;
      # now q is the U_i-minimal element in qU_i
      # v is now [true,stabilizer information]

    fi;

    if IsStabIterator(stab) then
        stab!.i := i;
        stab!.info := v[2];
        stab!.pos := List([1..i],x->1);
    fi;

    # now we are on the minimal element in the S-orbit
#Print("raus\n");
    return p;
  fi;
end );


#######################
# Suborbit databases: #
#######################

InstallMethod( SuborbitDatabase, "for an orbit by suborbit setup object",
  [ IsOrbitBySuborbitSetup, IsPosInt ],
  function( setup, hashlen )
    local r;
    r := rec( reps := [], lengths := [], setup := setup, totallength := 0 );
    r.mins := NewHT( setup!.sample[setup!.k+1], hashlen );
    Objectify( StdSuborbitDatabasesType, r );
    return r;
  end );

InstallMethod( ViewObj, "for a suborbit database",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep ],
  function( db )
    Print( "<suborbit database with ",Length(db!.reps)," suborbits, total ",
           "size: ", Sum(db!.lengths), ">" );
  end );

InstallMethod( StoreSuborbit, 
  "for a suborbit database, a point, a stabiterator, and a setup object",
  [ IsSuborbitDatabase and IsStdSuborbitDbRep, IsObject, IsStabIterator ],
  function(db,p,stab)
  # "db" must be a suborbit database
  # "p" must be a U-minimal element, which is not yet known
  # "stab" must be stabilizer information coming from minimalization
  # all U-minimal elements in the same orbit are calculated and stored
  # in the hash, in addition "p" is appended as representative to
  # "suborbits" and the orbit length is calculated and appended to
  # "lengths".
  local setup, k, firstgen, lastgen, li, i, j, pp, vv, nrmins, length,stabsize;
        
  setup := db!.setup;
  k := setup!.k;
  Add(db!.reps,p);
  AddHT(db!.mins,p,Length(db!.reps));
  ###Print("[",Product(stab.info,Length),"\c");
  if Size(stab) = setup!.size[k] then
    # better use a standard orbit algorithm:
    if k = 1 then
      firstgen := 1;
    else
      firstgen := Length(setup!.els[k-1])+1;
    fi;
    lastgen := Length(setup!.els[k]);
    li := [p];
    i := 1;
    while i <= Length(li) do
      for j in [firstgen..lastgen] do
        pp := setup!.op[k+1](li[i],setup!.els[k+1][j]);  # ???
        vv := ValueHT(db!.mins,pp);
        if vv = fail then
          AddHT(db!.mins,pp,Length(db!.reps));
          Add(li,pp);
        fi;
      od;
      i := i + 1;
    od;
    nrmins := Length(li);
    length := nrmins;
  else
    Reset(stab);
    nrmins := 1;
    stabsize := 0;
    repeat
      pp := ORB_ApplyStabElement(p,k+1,k,setup,stab,false);
      if p = pp then  # we got a real stabilizer element of p
        stabsize := stabsize + 1;
      else  # we could have stepped to some other U-minimal element
        vv := ValueHT(db!.mins,pp);
        if vv = fail then
          AddHT(db!.mins,pp,Length(db!.reps));
          nrmins := nrmins+1;
        fi;
      fi;
    until Next(stab);
    length := setup!.size[k] / stabsize;
  fi;
  Add(db!.lengths,length);
  db!.totallength := db!.totallength + length;
  ###Print("]\r");
  Print("]\rNew #",Length(db!.reps),
        ", size ",ORB_PrettyStringBigNumber(length),", ");
  Print("NrMins: ",nrmins,", ");
  return length;
end );


InstallGlobalFunction( OrbitBySuborbit,
function(p,hashlen,size,setup,percentage)
  # Enumerates the orbit of p under the group G generated by "gens" by
  # suborbits for the subgroup U described in "setup". 
  # "p" is a point
  # "hashlen" is an upper bound for the set of U-minimal points in the G-orbit
  # "size" is the group order to stop when we are ready and as upper bound
  #        for the orbit length
  # "setup" is a setup object for the iterated quotient trick,
  #         effectively enabling us to do minimalization with a subgroup
  # "percentage" is a number between 50 and 100 and gives a stopping criterium.
  #         We stop if percentage of the orbit is enumerated.
  #         Only over 50% we know that the stabilizer is correct!
  # Returns a suborbit database with additional field "words" which is
  # a list of words in gens which can be used to reach U-orbit in the G-orbit

  local k,firstgen,lastgen,stab,miniwords,db,stabgens,stabperms,stabilizer,
        fullstabsize,words,todo,i,j,x,mw,done,newperm,newword,oldtodo,sw,xx,v;

  # Setup some shortcuts:
  k := setup!.k;
  firstgen := Length(setup!.els[k])+1;
  lastgen := Length(setup!.els[k+1]);

  # First we U-minimalize p:
  stab := StabIterator();
  p := ORB_Minimalize(p,k+1,k,setup,stab,false);

  miniwords := [[]];  # here we collect U-minimalizing elements
  
  # Start a database with the first U-suborbit:
  db := SuborbitDatabase(setup,hashlen);
  StoreSuborbit(db,p,stab);

  stabgens := [];
  stabperms := [];
  stabilizer := Group(setup!.permgens[1]^0);
  if IsBound( setup!.stabchainrandom ) then
      StabChain( stabilizer, rec( random := setup!.stabchainrandom ) );
  else
      StabChain(stabilizer);
  fi;
  fullstabsize := 1;
  
  words := [[]];
  todo := [[]];
  while true do

    i := 1;
    while i <= Length(todo) do
      for j in [firstgen..lastgen] do
        x := setup!.op[k+1](p,setup!.els[k+1][j]);   # ???
        x := ORB_ApplyWord(x,todo[i],setup!.els[k+1],
                           setup!.elsinv[k+1],stab!.op[k+1]);   # ???
        mw := [];
        x := ORB_Minimalize(x,k+1,k,setup,stab,mw);
        v := ValueHT(db!.mins,x);
        if v = fail then
          Add(words,Concatenation([j],todo[i]));
          Add(todo,Concatenation([j],todo[i]));
          Add(miniwords,mw);
          StoreSuborbit(db,x,stab);
          Print("total: ",ORB_PrettyStringBigNumber(db!.totallength),
                " stab: ",ORB_PrettyStringBigNumber(fullstabsize),"       \r");
          if 2 * db!.totallength * fullstabsize > size and
             db!.totallength * fullstabsize >= QuoInt(size*percentage,100) then 
            Print("\nDone!\n");
            return rec(db := db,
                       words := words,
                       fullstabsize := fullstabsize,
                       groupsize := size,
                       orbitlength := size/fullstabsize,
                       percentage := percentage);
          fi;
        else
          if db!.totallength * fullstabsize * 2 <= size then
            # otherwise we know that we will not find more stabilizing els.
            # we know now that v is an integer and that
            # p*setup!.els[j]*todo[i]*U = p*words[v]*U
            # p*setup!.els[j]*todo[i]*mw is our new vector
            # p*words[v]*miniwords[v] is our old vector
            # they differ by an element in Stab_U(...)
            Reset(stab);
            done := false;
            repeat
              sw := [];
              xx := ORB_ApplyStabElement(x,k+1,k,setup,stab,sw);
              if xx = db!.reps[v] then  
                # we got a real stabilizer element of p
                done := true;
                newword := Concatenation([j],todo[i],mw,sw,
                            ORB_InvWord(miniwords[v]),ORB_InvWord(words[v]));
                newperm := ORB_ApplyWord((),newword,
                                 setup!.permgens,setup!.permgensinv,OnRight);
                ###Print(".\c");
                if not(IsOne(newperm)) then
                  if not(newperm in stabilizer) then
                    Add(stabgens,newword);
                    Add(stabperms,newperm);
                    stabilizer := GroupWithGenerators(stabperms);
                    Print("\nCalculating new estimate of the stabilizer...\c");
                    if IsBound(setup!.stabchainrandom) then
                        StabChain(stabilizer, 
                                  rec(random := setup!.stabchainrandom));
                    else
                        StabChain(stabilizer);
                    fi;
                    fullstabsize := Size(stabilizer);
                    Print("done.\nNew stabilizer order: ",fullstabsize,"\n");
                    if db!.totallength * fullstabsize 
                       >= QuoInt(size*percentage,100) then 
                      Print("\nDone!\n");
                      return rec(db := db,
                                 words := words,
                                 fullstabsize := fullstabsize,
                                 groupsize := size,
                                 orbitlength := size/fullstabsize,
                                 percentage := percentage);
                    fi;
                  fi;
                fi;
              fi;
            until done or Next(stab);
          fi;
        fi;
      od;
      i := i + 1;
    od;
  
    oldtodo := todo;
    todo := [];
    for i in [1..Length(stabgens)] do
      Append(todo,List(oldtodo,w->Concatenation(stabgens[i],w)));
    od;
    Print("\nLength of next todo: ",Length(todo),"\n");
  od;
  # this is never reached
end );

# FIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXME
# VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV

InstallGlobalFunction( ORB_NextStabIterator2,
function(stab)
  local i;
  i := stab.i;
  while true do
    if i < 1 then
      return true;   # finished with this iterator
    fi;
    stab.pos[i] := stab.pos[i]+1;
    #stab.point[i] := [];    # this is no longer valid
    if stab.pos[i] <= Length(stab.info[i]) then
      return false;  # next element found
    fi;
    stab.pos[i] := 1;
    i := i - 1;
  od;
  # this is never reached
end );

InstallGlobalFunction( ORB_ApplyUElement,
function(p,j,stabel,i,setup,stab,w)
  local ww;
  while i >= 1 do
    ww := ShallowCopy(setup.trans[i][stab.info[i][stabel[i]]]);
    if IsList(w) then Append(w,ww); fi;
    p := ORB_ApplyWord(p,ww,setup.els[j],setup.elsinv[j],setup.op[j]); # FIXME
    i := i - 1;
  od;
  return p;
end );

InstallGlobalFunction( OrbitBySuborbitWithKnownSize,
function(p,gens,op,hashlen,size,setup,randels)
  # Enumerates the orbit of p under the group G generated by "gens" by
  # suborbits for the subgroup U described in "setup". 
  # "p" is a point
  # "gens" is a list of generators for a group
  # "op" is a function for the operation op(p,gens[...]) should be defined
  # "hashlen" is an upper bound for the set of U-minimal points in the G-orbit
  # "size" is the group order to stop when we are ready and as upper bound
  #        for the orbit length
  # "setup" is a record of data for the iterated quotient trick,
  #         effectively enabling us to do minimalization with a subgroup
  # "randels" number of random elements to use for recognising half orbits
  # Returns a triple:
  #   First entry is a list of U-minimal points in the orbit, one for 
  #     each U-orbit in the G-orbit
  #   Second entry is the length of each U-orbit in the G-orbit
  #   Third entry is a list of words in gens which can be used to reach 
  #     U-orbit in the G-orbit
  local StoreSubOrbit,ht,i,ii,j,l,lengths,q,stab,suborbits,totallength,
        trans,v,w,ww,x,y,z,Ucounter,g;

  StoreSubOrbit := function(p,stab)
    # "p" must be a U-minimal element, which is not yet known
    # "stab" must be stabilizer information coming from minimalization
    # all U-minimal elements in the same orbit are calculated and stored
    # in the hash, in addition "p" is appended as representative to
    # "suborbits" and the orbit length is calculated and appended to
    # "lengths".
    local firstgen,i,j,lastgen,li,length,nrmins,pp,stabsize,vv;
    Add(suborbits,p);
    AddHT(ht,p,Length(suborbits));
    Print("[",Product(stab.info,Length),"\c");
    if Product(stab.info,Length) = setup.size[setup.k] then
      # better use a standard orbit algorithm:
      if setup.k = 1 then
        firstgen := 1;
      else
        firstgen := Length(setup.els[setup.k-1])+1;
      fi;
      lastgen := Length(setup.els[setup.k]);
      li := [p];
      i := 1;
      while i <= Length(li) do
        for j in [firstgen..lastgen] do
          pp := op(li[i],setup.els[setup.k+1][j]);
          vv := ValueHT(ht,pp);
          if vv = fail then
            AddHT(ht,pp,Length(suborbits));
            Add(li,pp);
          fi;
        od;
        i := i + 1;
      od;
      nrmins := Length(li);
      length := nrmins;
    else
      Reset(stab);
      nrmins := 1;
      stabsize := 0;
      repeat
        pp := ORB_ApplyStabElement(p,setup.k+1,setup.k,setup,stab,false);
        if p = pp then  # we got a real stabilizer element of p
          stabsize := stabsize + 1;
        else  # we could have stepped to some other U-minimal element
          vv := ValueHT(ht,pp);
          if vv = fail then 
            if AddHT(ht,pp,Length(suborbits)) = fail then
              Error("Hash table full!");
            fi;
            nrmins := nrmins+1;
          fi;
        fi;
      until Next(stab);
      length := setup.size[setup.k] / stabsize;
    fi;
    Add(lengths,length);
    Print("]\rStored new suborbit #",Length(suborbits),
          " of size ",ORB_PrettyStringBigNumber(length),
          " NrMins: ",nrmins," ");
    return length;
  end;

  # First we U-minimalize p:
  stab := rec();
  q := ORB_Minimalize(p,setup.k+1,setup.k,setup,stab,false);

  suborbits := [];  # here we collect U-minimal elements for the U-suborbits
  lengths := [];    # here we collect U-suborbit lengths
  trans := [[]];    # words for getting to the U-suborbits
  
  # was: ht := InitHT(hashlen,hashfunc,EQ);
  ht := NewHT(q,hashlen);
  totallength := StoreSubOrbit(q,stab);

  l := [p];
  i := 1;   # counts elements in l
  # use a stabilizer info, which describes all of U:
  Ucounter := rec();
  Ucounter.i := setup.k;
  Ucounter.info := List([1..setup.k],i->[1..setup.index[i]]);
  Ucounter.pos := List([1..setup.k],i->1);

  # Throw in some vectors gotten by applying random elements:
  g := Group(gens);
  for j in [1..randels] do
      Print("Applying random element ",j," (",randels,") ...\n");
      x := p * PseudoRandom(g);
      y := ORB_Minimalize(x,setup.k+1,setup.k,setup,stab,false);
      v := ValueHT(ht,y);
      if v = fail then
          Add(l,x);
          Add(trans,[fail]);
          totallength := totallength + StoreSubOrbit(y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(totallength),"      \n");
      fi;
      if totallength >= size then 
        Print("\nDone.\n");
        return rec( minreps := suborbits,
                    reps := l,
                    lengths := lengths,
                    words := trans,
                    ht := ht ); 
      fi;
  od;
  Unbind(g);
   
  ORB_NextStabIterator2(Ucounter);
  repeat
    while i <= Length(l) do
      for j in [1..Length(gens)] do
        x := op(l[i],gens[j]);
        y := ORB_Minimalize(x,setup.k+1,setup.k,setup,stab,false);
        v := ValueHT(ht,y);
        if v = fail then
          Add(trans,Concatenation(trans[i],[j]));
          Add(l,x);
          totallength := totallength + StoreSubOrbit(y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(totallength),"      \r");
          if totallength >= size then 
            Print("\nDone.\n");
            return rec( minreps := suborbits,
                        reps := l,
                        lengths := lengths,
                        words := trans,
                        ht := ht ); 
          fi;
        fi;
      od;
      i := i + 1;
    od;
    # now we have to to something else, perhaps applying some U elements?
    Print(".\c");
    for ii in [1..Length(l)] do
      w := [];
      z := ORB_ApplyUElement(l[ii],setup.k+1,Ucounter.pos,setup.k,
                             setup,Ucounter,w);
      for j in [1..Length(gens)] do
        x := op(z,gens[j]);
        y := ORB_Minimalize(x,setup.k+1,setup.k,setup,stab,false);
        v := ValueHT(ht,y);
        if v = fail then
          Add(trans,Concatenation(trans[ii],w,[j]));
          Add(l,x);
          totallength := totallength + StoreSubOrbit(y,stab);
          Print("total: ",ORB_PrettyStringBigNumber(totallength),"       \r");
          if totallength >= size then 
            Print("\nDone.\n");
            return rec( minreps := suborbits,
                        reps := l,
                        lengths := lengths,
                        words := trans,
                        ht := ht ); 
          fi;
        fi;
      od;
    od;
  until ORB_NextStabIterator2(Ucounter);

  Print("Warning! Orbit not complete!!!\n");
  # this should never happen!
  return rec( minreps := suborbits,
              reps := l,
              lengths := lengths,
              words := trans,
              ht := ht ); 
end );

# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# FIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXMEFIXME

############################
# Convenient preparations: #
############################

InstallGlobalFunction( OrbitBySuborbitBootstrapForVectors,
function(gens,permgens,sizes,codims)
  # Returns a setup object for a list of helper subgroups
  # gens: a list of lists of generators for U_1 < U_2 < ... < U_k < G
  # permgens: the same in a faithful permutation representation
  # sizes: a list of sizes of groups U_1 < U_2 < ... < U_k
  # codims: a list of dimensions of factor modules
  # note that the basis must be changed to make projection easy!
  # That is, projection is taking the components [1..codim].

  local dim,doConversions,f,i,j,k,nrgens,nrgenssum,o,regvec,setup,sum,v;

  # For the old compressed matrices:
  if IsGF2MatrixRep(gens[1][1]) or Is8BitMatrixRep(gens[1][1]) then
      doConversions := true;
  else
      doConversions := false;
  fi;

  # Some preparations:
  k := Length(sizes);
  if Length(gens) <> k+1 or Length(permgens) <> k+1 or Length(codims) <> k then
      Error("Need generators for ",k+1," groups and ",k," codimensions.");
      return;
  fi;
  nrgens := List(gens,Length);
  nrgenssum := 0*nrgens;
  sum := 0;
  for i in [1..k+1] do
      nrgenssum[i] := sum;
      sum := sum + nrgens[i];
  od;
  nrgenssum[k+2] := sum;

  # Do the first step:
  setup := rec(k := 1);
  setup.size := [sizes[1]];
  setup.index := [sizes[1]];
  setup.permgens := Concatenation(permgens);
  setup.permgensinv := List(setup.permgens,x->x^-1);
  setup.els := [];
  dim := Length(gens[1][1]);
  codims[k+1] := dim;   # for the sake of completeness!
  setup.els[1] := List(gens[1],x->ExtractSubMatrix(x,[1..codims[1]],
                                                     [1..codims[1]]));
  if k = 1 then   # only one step to prepare!
      setup.els[2] := Concatenation(gens[1],gens[2]);
  else
      setup.els[2] := Concatenation(
          List(gens[1],x->ExtractSubMatrix(x,[1..codims[2]],[1..codims[2]])),
          List(gens[2],x->ExtractSubMatrix(x,[1..codims[2]],[1..codims[2]])));
  fi;
  if doConversions then
      for i in setup.els[1] do ConvertToMatrixRep(i); od;
      for i in setup.els[2] do ConvertToMatrixRep(i); od;
  fi;
  setup.elsinv := List(setup.els,l->List(l,x->x^-1));
  f := BaseField(gens[1][1]);
  regvec := ZeroVector(gens[1][1],codims[1]);  
            # a new empty vector over same field
  Print("Looking for regular U1-orbit...\n");
  repeat
      Randomize(regvec);
      o := Enumerate(InitOrbit(setup.els[1],regvec,OnRight,sizes[1]*2));
      Print("Found length: ",Length(o!.orbit),"        \r");
  until Length(o!.orbit) = sizes[1];
  Print("\nFound!\n");
  setup.trans := List([1..Length(o!.orbit)],i->TraceSchreierTreeForward(o,i));

  # Note that for k=1 we set codims[2] := dim
  setup.pi := [];
  setup.pi[2] := [];
  setup.pi[2][1] := [1..codims[1]];
  setup.pifunc := [];
  setup.pifunc[2] := [];
  setup.pifunc[2][1] := \{\};
  setup.info := [NewHT(regvec,Size(f)^(codims[1]) * 2)];
  setup.suborbnr := [0];
  setup.sumstabl := [0];
  setup.regvecs := [regvec];
  setup.cosetinfo := [];
  setup.cosetrecog := [];

  Objectify( NewType( OrbitBySuborbitSetupFamily,
                      IsOrbitBySuborbitSetup and IsStdOrbitBySuborbitSetupRep ),
             setup );
  # From now on we can use it and it is an object!

  # Now do the other steps:
  for j in [2..k] do
      # First find a vector the orbit of which identifies the U_{j-1}-cosets
      # of U_j, i.e. Stab_{U_j}(v) <= U_{j-1}, 
      # we can use the j-1 infrastructure!
      v := ZeroVector(v,codims[j]);
      Print("Looking for U",j-1,"-coset-recognising U",j,"-orbit\n");
      repeat
          Print("Trying vector...\n");
          regvec := ShallowCopy(v);
          Randomize(regvec);
          o := OrbitBySuborbit(regvec,
                   setup!.els[j]{[nrgenssum[j]+1..nrgenssum[j]+nrgens[j]]},
                   OnRight,sizes[j]*2+1,sizes[j],setup);
      until Sum(o[2]) = sizes[j];
      Print("Found regular orbit!\n");
      setup!.k := j;
      setup!.size[j] := sizes[j];
      setup!.index[j] := sizes[j]/sizes[j-1];
      setup!.els[j+1] := [];
      for i in [1..j+1] do
          if j = k then
              Append(setup!.els[j+1],gens[i]);
          else
              Append(setup!.els[j+1],
                List(gens[i],x->x{[dim-codims[j+1]+1..dim]}
                                 {[dim-codims[j+1]+1..dim]}));
          fi;
      od;
      for i in setup!.els[j+1] do
          ConvertToMatrixRep(i);
      od;
      setup!.elsinv[j+1] := List(setup!.els[j+1],x->x^-1);
      setup!.pi[j+1] := [];
      for i in [1..j] do
          setup!.pi[j+1][i] := [codims[j+1]-codims[i]+1..codims[j+1]];
      od;
      setup!.trans[j] := List(o[3],x->x + nrgenssum[j]);
      setup!.suborbnr[j] := 0;
      setup!.sumstabl[j] := 0;
      setup!.info[j] :=
NewHT(regvec,QuoInt(Size(f)^(codims[j]),sizes[j-1])*30+1); # fixme!
      setup!.regvecs[j] := regvec;
      setup!.cosetinfo[j] := o[4];   # the hash table
      setup!.cosetrecog[j] := function(w,s)
        local x;
        x := ORB_ApplyWord(s.regvecs[j],w,s.els[j],s.elsinv[j],OnRight);
        x := ORB_Minimalize(x,j,j-1,s,false,false);
        return ValueHT(s.cosetinfo[j],x);
      end;
  od;
  return setup;
end );

