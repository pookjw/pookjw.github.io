# NSDiffableDataSourceSnapshot의 몇가지 팁

`NSDiffableDataSourceSnapshot`에 대한 정보가 너무 부족해서 ~_~ 적는 글입니다. iOS 15.0 beta 8 SDK 기준입니다.

## reload VS reconfigure

iOS 15.0에서 `NSDiffableDataSourceSnapshot`에  `reconfigure`라는 개념이 추가되었습니다. ([문서](https://developer.apple.com/documentation/uikit/nsdiffabledatasourcesnapshot/3801890-reconfigureitemswithidentifiers?language=objc))

```objective-c
// Reconfigures any existing cells for the items. Reconfiguring is more efficient than reloading an item, as it does not replace the
// existing cell with a new cell. Prefer reconfiguring over reloading unless you actually need an entirely new cell for the item.
- (void)reconfigureItemsWithIdentifiers:(NSArray<ItemIdentifierType>*)identifiers API_AVAILABLE(ios(15.0), tvos(15.0));
```

`reload`는 iOS 13.0 부터 있던 개념이기도 한데요. 이 둘의 차이점을 나열하자면

### Cell Reuse

- `reload`가 걸리는 Item은 cell이 reuse되지 않고 재생성 됩니다. 따라서 애니메이션이 매끄럽지 못할 수 있습니다. 특히 `trailingSwipeActionsConfigurationProvider` ([문서](https://developer.apple.com/documentation/uikit/uicollectionlayoutlistconfiguration/3650428-trailingswipeactionsconfiguratio?language=objc)) 같은 것을 쓴다면 더욱 어색하게 보이겠지요.
- 반대로 `reconfigure`는 cell을 reuse 할 수 있습니다. 
- 하지만 주의해야 할 점은, 이전 snapshot의 Item 목록에서, reconfigure할 Item의 hash 값이 존재할 경우에만 reconfigure가 작동합니다. 이전 snapshot의 Item 목록에서, reconfigure할 Item의 hash 값이 존재하지 않는데 reconfigure를 시도한다? 그러면 아무 일도 발생하지 않습니다.
- 또 하나 주의해야 할 점은, 새로운 snapshot에서 Item이 삭제되고 다시 추가(append)할 경우, 이전 snapshot에 reconfigure할 Item의 hash가 존재했어도 reconfigure는 작동하지 않습니다.
- 따라서 `reconfigure`를 발동시킬 수 있는 조건은 아래와 같습니다.
  1. 이전 snapshot의 Item 목록에서, reconfigure할 Item의 hash가 존재해야 한다.
  2. 새로운 snapshot에는 reconfigure할 Item이 삭제되었다가 다시 추가되어서는 안 된다.

### Exception

- reload가 걸릴려면, Item의 hash 값이 이전 snapshot에 존재해야 합니다. 안 그러면 Exception이 일어납니다.
- reconfigure는 이전 snapshot에 Item의 hash가 없는 상태에서, reconfigure를 시도해도 Exception은 일어나지 않습니다. 다만, Cell Reuse에서 언급했듯이 아무 일도 일어나지 않습니다.

### 결론

iOS 15.0 미만에서는 어쩔 수 없이 reload를 써야 하지만, iOS 15.0 이상이라면 reconfigure를 쓰는게 좋습니다. 단, 위 조건에 부합하도록 설계해야 합니다.

## Sort

이유를 모르겠으나 [NSDiffableDataSourceSnapshot](https://developer.apple.com/documentation/uikit/nsdiffabledatasourcesnapshot?language=objc)에서는 sort를 제공하지 않습니다. snapshot을 mutate 시킬려면 애플이 만들어놓은 method 안에서만 해야 해서, Swift/Objective-C에 내장된 Sort 함수를 쓸 수 없습니다.

그런 분들을 위해 제가 [SortSnapshot](https://github.com/pookjw/SortSnapshot)라는 라이브러리를 만들었습니다. 아래는 제 개인 프로젝트에서 timestamp (NSDate) 순서대로 Item을 sort 시키는 코드입니다. 코드 몇줄만 써서 sort를 시킬 수 있습니다.

```objective-c
- (void)sortSnapshot:(NSDiffableDataSourceSnapshot *)snapshot {
    [snapshot ssSortItemsWithSectionIdentifiers:snapshot.sectionIdentifiers
                              usingComparator:^NSComparisonResult(DecksItemModel *obj1, DecksItemModel *obj2) {
        if ((obj1 == nil) || (obj2 == nil)) {
            return NSOrderedSame;
        }
        return [obj2.localDeck.timestamp compare:obj1.localDeck.timestamp];
    }];
}
```

### isEqual, hash

NSObject에서는 `isEqual:`과 `hash` method를 제공합니다.

```objective-c
- (BOOL)isEqual:(id)object;
 
- (NSUInteger)hash;  
```

이 둘은 NSDiffableDataSourceSnapshot에서 Item을 비교할 때 쓰이지만, 어떨 때 `isEqual:`이 쓰이고, 어떨 때 `hash`가 쓰이지? 라는 의문이 생기더라고요. 이를 정리하면

- 하나의 snapshot 내에서는 `isEqual:`이 쓰입니다. 어떤 아이템을 `delete`, `move` 같은 걸 할 때 `isEqual:`로 통해 snapshot이 가지고 있는 Item과 비교해서 `delete`, `move` 같은 동작을 합니다. 따라서, 두개의 Item의 reference가 달라도 `isEqual:`로 통해 Item이 둘이 같다는 결과가 나오면, snapshot에서는 똑같다고 치부합니다.
- 새로운 snapshot을 반영하기 위해, 이전 snapshot과 diff 연산하는 과정에서는 `hash` 비교가 쓰입니다.
- `isEqual:`로 통해 두개의  Item이 똑같다고 하는데 `hash` 값이 다르다면 Exception이 일어납니다.

