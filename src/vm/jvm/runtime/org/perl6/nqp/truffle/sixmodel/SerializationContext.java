package org.perl6.nqp.truffle.sixmodel;

import java.util.ArrayList;
import java.util.HashMap;

public final class SerializationContext {
    /* The handle of this SC. */
    public String handle;

    /* Description (probably the file name) if any. */
    public String description;

    /* The root set of objects that live in this SC. */
    private ArrayList<Object> rootObjects;

    /* The root set of STables that live in this SC. */
    private ArrayList<STable> rootSTables;

    public SerializationContext(String handle) {
        this.handle = handle;
        this.rootObjects = new ArrayList<Object>();
        this.rootSTables = new ArrayList<STable>();
    }

    public void initSTableList(int entries) {
        rootSTables.ensureCapacity(entries);
        for (int i = 0; i < entries; i++)
            rootSTables.add(null);
    }

    private HashMap<STable, Integer> stableIndexCache = new HashMap<STable, Integer>();
    public void addSTable(STable stable) {
        int newIndex = rootSTables.size();
        rootSTables.add(stable);
        stableIndexCache.put(stable, new Integer(newIndex));
    }

    public void setSTable(int index, STable stable) {
        rootSTables.set(index, stable);
        stableIndexCache.put(stable,  new Integer(index));
    }

    public int getSTableIndex(STable stable) {
        Integer cachedIndex = stableIndexCache.get(stable);
        if (cachedIndex != null) {
            return cachedIndex.intValue();
        } else {
            return -1;
        }
    }

    public STable getSTable(int index) {
        return rootSTables.get(index);
    }

    public int stableCount() {
        return rootSTables.size();
    }

    private HashMap<Object, Integer> objectIndexCache = new HashMap<Object, Integer>();

    public void initObjectList(int entries) {
        rootObjects.ensureCapacity(entries);
        for (int i = 0; i < entries; i++)
            rootObjects.add(null);
    }

    public void addObject(Object obj) {
        int newIndex = rootObjects.size();
        rootObjects.add(obj);
        objectIndexCache.put(obj, new Integer(newIndex));
    }

    public void addObject(Object obj, int index) {
        if (index == rootObjects.size()) {
            rootObjects.add(obj);
        } else {
            rootObjects.set(index,  obj);
        }
        objectIndexCache.put(obj, new Integer(index));
    }

    public int getObjectIndex(Object obj) {
        Integer cachedIndex = objectIndexCache.get(obj);
        if (cachedIndex != null) {
            return cachedIndex.intValue();
        } else {
            return -1;
        }
    }

    public Object getObject(int index) {
        return rootObjects.get(index);
    }

    public int objectCount() {
        return rootObjects.size();
    }

}
