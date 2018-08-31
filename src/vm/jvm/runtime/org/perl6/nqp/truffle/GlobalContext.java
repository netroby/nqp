package org.perl6.nqp.truffle;

import org.perl6.nqp.truffle.runtime.HLL;
import org.perl6.nqp.truffle.sixmodel.SerializationContext;

import java.util.ArrayList;
import java.util.HashMap;

public class GlobalContext {
    public HashMap<String, HLL> hlls;
    public HashMap<String, SerializationContext> scs;
    public ArrayList<SerializationContext> compilingSCs;

    public GlobalContext() {
        hlls = new HashMap<String, HLL>();
        scs = new HashMap<String, SerializationContext>();
        compilingSCs = new ArrayList<SerializationContext>();
    }
}

